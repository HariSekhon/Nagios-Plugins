#!/usr/bin/perl
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-09-22 18:54:39 +0100 (Sun, 22 Sep 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check MongoDB via API by writing a unique document and then reading it back

It will find and connect to the Primary from the given list of Mongod / Mongos nodes. Failing to find a viable Primary will result in the whole check aborting as the replica set / cluster is non-writable in that scenario.

Once it connects to the Primary, it will perform the following checks:

1. write a new unique document to the nagios collection with dynamically generated value
2. read the same document back, checking the value is identical to the value generated and written
3. delete the just created document
4. records the write/read/delete timings to a given precision and outputs perfdata for graphing
5. compares each operation's time taken against the warning/critical thresholds if given

Tested on MongoDB 2.4.8, 2.6.1, 3.2.1 - standalone mongod, mongod Replica Sets, mongos with Sharded Replica Sets, with and without authentication

Write concern and Read concern take the following options with --write-concern and --read-concern:

'1'         = primary only
'2'         = primary + 1 secondary replica
'N'         = N number of Mongod instances must acknowledge including Primary
'majority'

The query timeout for each write => read => delete operation is one quarter of the global --timeout

MongoDB Library Limitations:

- Error Handling: the MongoDB Perl library has some limitations around the way it handles exceptions and error reporting. As a result, connection problems and failure to find a master result in an incorrect error message 'Operation now in progress' if attempting to handle and prefix with CRITICAL, so they have been left bare to report the correct errors. The correct Nagios error code of CRITICAL (2) is still enforced via the library HariSekhonUtils regardless
  - Specifying a list of nodes in a Replica Set where none of the nodes are Primary results in 'not master at check_mongodb_write.pl ...'
- Write Concern:
    - Using write concern 'all' is not supported, it should work in theory according to the library documentation but in reality it does not work so has been disallowed as an option
    - Using anything other than 1 with a stand alone Mongod causes results in 'repl at check_mongodb_write.pl line 221'. This is unintuitive but basically means there is no replication / Replica Set for the value to be valid
    - Because of these behaviours, the write concern is set to 'majority' if more than one node is specified and '1' otherwise. This can be overridden using --write-concern
    - Using a write-concern higher than the number of members of a Replica Set will result in a timeout error from the library (wtimeout which defaults to 1 second)
";

$VERSION = "0.6.0";

# TODO: Read Preference straight pass thru qw/primary secondary primaryPreferred secondaryPreferred nearest/
# TODO: check_mongodb_write_replication.pl link and enforce secondary Read Preference

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MongoDB;
# XXX: there is a bug in the Readonly module that MongoDB::MongoClient uses. It tries to call Readonly::XS but there is some kind of MAGIC_COOKIE mismatch and Readonly::XS errors out with:
#
# Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
#
# Workaround is to edit Readonly.pm and comment out line 33 which does the eval 'use Readonly::XS';
# On Linux this is located at:
#
# /usr/local/share/perl5/Readonly.pm
#
# On my Mac OS X Mavericks:
#
# /Library/Perl/5.16/Readonly.pm
#
use Data::Dumper;
use MongoDB::MongoClient;
use Sys::Hostname;
use Time::HiRes 'time';

my $database          = "nagios";
( my $default_collection = $progname ) =~ s/\.pl$//;
my $collection = $default_collection;

my $write_concern;
my $read_concern;

my $default_wtimeout  = 1000;
my $wtimeout          = $default_wtimeout;

my $default_precision = 4;
my $precision         = $default_precision;

%options = (
    %mongo_host_option,
    #"P|port=s",        => $hostoptions{"P|port=s"},
    #"P|port=s"         => [ \$port,          "Port to connect to (\$MONGODB_PORT, \$PORT, default: $default_port)" ],
    "d|database=s"     => [ \$database,      "Database to use (default: nagios)" ],
    "C|collection=s"   => [ \$collection,    "Collection to write test document to (default: $default_collection)" ],
    %useroptions,
    "write-concern=s"  => [ \$write_concern, "MongoDB write concern (defaults to '1' for a single node or 'majority'. See --help for details in header description)" ],
    "read-concern=s"   => [ \$read_concern,  "MongoDB read  concern (defaults to '1' for a single node or 'majority'. See --help for details in header description)" ],
    #"wtimeout=s"       => [ \$wtimeout,      "Number of milliseconds an operations should wait for w slaves to replicate it (defaults to $default_wtimeout ms)" ],
    %mongo_sasl_options,
    "w|warning=s"      => [ \$warning,       "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "c|critical=s"     => [ \$critical,      "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "precision=i"      => [ \$precision,     "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port database collection user password write-concern read-concern wtimeout ssl sasl sasl-mechanism warning critical precision/;
get_options();

$hosts       = validate_mongo_hosts($host);
$database    = validate_database($database, "Mongo");
$collection  = validate_collection($collection, "Mongo");
#unless(($user + $password) / 2 == 0) {
#    usage "--user and --password must both be specified if one of them are";
#}
$user        = validate_user($user)         if defined($user) and defined($password);
$password    = validate_password($password) if defined($password);
if(scalar @hosts == 1){
    $write_concern = 1 unless defined($write_concern);
    $read_concern  = 1 unless defined($read_concern);
} else {
    $write_concern = "majority" unless defined($write_concern);
    $read_concern  = "majority" unless defined($read_concern);
}
if(isInt($write_concern)){
    $write_concern = int($write_concern) if isInt($write_concern);
    usage "--write-concern may not be zero!" unless $write_concern;
} else {
    grep { $write_concern eq $_ } @valid_concerns  or usage "invalid write concern given";
}
if(isInt($read_concern)){
    $read_concern  = int($read_concern)  if isInt($read_concern);
    usage "--read-concern may not be zero!" unless $read_concern;
} else {
    grep { $read_concern  eq $_ } @valid_concerns  or usage "invalid read concern given";
}
vlog_option "write concern", $write_concern;
vlog_option "read concern",  $read_concern;
validate_int($wtimeout, "wtimeout", 1, 1000000);
validate_mongo_sasl();
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );
validate_int($precision, "precision", 1, 20);
unless($precision =~ /^(\d+)$/){
    code_error "precision is not a digit and has already passed validate_int()";
}
$precision = $1;
vlog2;

my $epoch      = time;
my $value      = random_alnum(20);
my $hostname   = hostname;
my $id         = "HariSekhon:$progname:$hostname:$epoch:" . substr($value, 0, 10);
my $document   = "{ '_id': '$id', 'value': '$value' }";
vlog_option "document", $document;

$status = "OK";

vlog2;
set_timeout();

my $start_time = time;
my $client = connect_mongo( $hosts,
                            {
                                "w"              => $write_concern,
                                "r"              => $read_concern,
                                "j"              => 1,
                            }
);

# API changed in Mongo::Client 1.0, no longer supports this
#if($user and $password){
#    vlog2 "authenticating against database '$database'";
#    try {
#        $client->authenticate($database, $user, $password) || quit "CRITICAL", "failed to authenticate: $!";
#    };
#    catch_quit "failed to authenticate";
#}

my $master;
if(defined($client->{'_master'}{'host'})){
    $master = $client->{'_master'}{'host'};
} elsif(defined($client->{'host'})){
    $master = $client->{'host'};
} else {
    quit "CRITICAL", "could not determine master\n";
}
$master =~ s,mongodb://,,;
# make default port implicit, only explicitly state non-default port
$master =~ s,:27017,,;
vlog2 "primary is $master\n";

my $db;
my $coll;

try {
    $db = $client->get_database($database)   || quit "CRITICAL", "failed to select database '$database': $!";
};
catch_quit "failed to select database '$database'";
vlog2 "selected database '$database'";

try {
    $coll = $db->get_collection($collection) || quit "CRITICAL", "failed to get collection '$collection': $!";
};
catch_quit "failed to get collection '$collection'";
vlog2 "got handle to collection '$collection'\n";

# ============================================================================ #
my $write_start = time;
my $returned_id;
try {
    $returned_id = $coll->insert_one(
        {
            '_id'   => $id,
            'value' => $value
        }
    ) or quit "CRITICAL", "failed to insert document in to database '$database' collection '$collection': $!";
};
catch{
    my $errmsg =  "failed to insert document in to database '$database' collection '$collection': $@";
    if($errmsg =~ /not master/){
        chomp $errmsg;
        $errmsg .= " You probably haven't specified the primary for the replica set in the list of MongoD instances? If you specified all MongoD instances in the replica set or connected via MongoS this may indicate a real problem. If you've got a sharded cluster and have specified the replica set directly you may have specified a replica set which isn't authoritative for the given shard key";
    } elsif($errmsg =~ /(<!, w)timeout/){
        chomp $errmsg;
        $errmsg .= " This can be caused by --write-concern being higher than the available replica set members";
    }
    quit "CRITICAL", $errmsg;
};
my $write_time = sprintf("%0.${precision}f", time - $write_start);
$msg .= "document written in $write_time secs";

unless($returned_id eq $id){
    quit "CRITICAL", "_id returned from insert ('$returned_id') was not as expected ('$id')";
}

vlog2 "wrote   document: $document";

# ============================================================================ #
my $count = 0;

my $read_start = time;
try {
    my $cursor = $coll->find( { '_id' => $id } );

    my $obj;
    while($cursor->has_next){
        $obj = $cursor->next;
        quit "CRITICAL", "document returned without _id"    unless defined($obj->{'_id'});
        quit "CRITICAL", "document returned without value"  unless defined($obj->{'value'});
        vlog2 "read    document: { '_id': '" . $obj->{"_id"} . "', 'value': '" . $obj->{'value'} . "' }";
        unless($obj->{'_id'} eq $id){
            quit "CRITICAL", "invalid _id returned from MongoDB, expected '$id', got '" . $obj->{_id} . "'";
        }
        unless($obj->{'value'} eq $value){
            quit "CRITICAL", "document's random value was read back incorrectly, wrote '$value', read '" . $obj->{value} . "'";
        }
        $count++;
    }
};
catch_quit "failed to read document back from collection '$collection' in database '$database'";
my $read_time = sprintf("%0.${precision}f", time - $read_start);
$msg .= ", read in $read_time secs";

if($count != 1){
    warning;
    $msg .= "$count results read back. $msg";
}

# ============================================================================ #

my $delete_start = time;
try {
    $coll->remove( { '_id' => $id } ) || quit "CRITICAL", "failed to delete document with _id: '$id'";
};
catch_quit "failed to delete document with _id: '$id'";
my $delete_time = sprintf("%0.${precision}f", time - $delete_start);
$msg .= ", deleted in $delete_time secs";

vlog2 "deleted document: { '_id': '$id' }\n";

my $msg_perf = " |";
my $msg_thresholds = msg_perf_thresholds(1);
$msg_perf .= " write_time=${write_time}s${msg_thresholds}";
$msg_perf .= " read_time=${read_time}s${msg_thresholds}";
$msg_perf .= " delete_time=${delete_time}s${msg_thresholds}";
$msg =~ s/^,\s*//;
check_thresholds($delete_time, 1);
check_thresholds($read_time, 1);
check_thresholds($write_time);
$msg .= $msg_perf;

quit $status, $msg;
