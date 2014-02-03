#!/usr/bin/perl
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-09-22 18:54:39 +0100 (Sun, 22 Sep 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check MongoDB is working by writing a unique document and then reading it back

It will find and connect to the Primary from the given list of Mongod / Mongos nodes. Failing to find a viable Primary will result in the whole check aborting as the replica set / cluster is non-writable in that scenario.

Once it connects to the Primary, it will perform the following checks:

1. write a new unique document to the nagios collection with dynamically generated value
2. read the same document back, checking the value is identical to the value generated and written
3. delete the just created document
4. records the write/read/delete timings to a given precision
5. compares each operation's time taken against the warning/critical thresholds if given

Tested on MongoDB 2.4.8, mongod with Replica Sets and mongos with Sharded Replica Sets with both sharded and non-sharded database collections

Limitations:

- The MongoDB Perl library has some limitations around the way it handles exceptions and error reporting. As a result, connection problems and failure to find a master result in an incorrect error message 'Operation now in progress' if attempting to handle and prefix with CRITICAL, so they have been left bare to report the correct errors. The correct Nagios error code of CRITICAL (2) is still enforced via the library HariSekhonUtils regardless
- The MongoDB Perl library does not respect the write concern and so at this time only 'majority' may be used, all other values result in 'exception: unrecognized getLastError mode: <mode>' despite the library documentation stating the other write-concern levels are respected
";

# Write concern and Read concern take the following options with --write-concern and --read-concern respectively:
# 
# '1' = primary only
# '2' = primary + 1 secondary replica
# 'majority'
# 'all'

$VERSION = "0.1";

# TODO: Read Preference straight pass thru qw/primary secondary primaryPreferred secondaryPreferred nearest/
# TODO: check_mongodb_write_replication.pl link and enforce secondary Read Preference

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
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
use MongoDB;
use MongoDB::MongoClient;
use Sys::Hostname;
use Time::HiRes 'time';

# not used
#set_port_default(27017);

env_creds("MongoDB");

my $database          = "nagios";
( my $default_collection = $progname ) =~ s/\.pl$//;
my $collection = $default_collection;

my @valid_concerns    = qw/1 2 majority all/;
my $default_concern   = "majority";
my $write_concern     = $default_concern;
my $read_concern      = $default_concern;

my $default_wtimeout  = 1000;
my $wtimeout          = $default_wtimeout;

my $ssl               = 0;
my $sasl              = 0;
my $sasl_mechanism    = "GSSAPI";

my $default_precision = 4;
my $precision         = $default_precision;

%options = (
    "H|host=s"         => [ \$host,          "MongoDB host(s) to connect to (should be from same replica set), comma separated, with optional :<port> suffixes. Tries hosts in given order from left to right to find Primary for write. Specifying any one host is sufficient as the rest will be auto-determined to find the primary (\$MONGODB_HOST, \$HOST)" ],
    #"P|port=s",        => $hostoptions{"P|port=s"},
    #"P|port=s"         => [ \$port,          "Port to connect to (\$MONGODB_PORT, \$PORT, default: $default_port)" ],
    "d|database=s"     => [ \$database,      "Database to use (default: nagios)" ],
    "C|collection=s"   => [ \$collection,    "Collection to write test document to (default: $default_collection)" ],
    %useroptions,
    #"write-concern=s"  => [ \$write_concern, "MongoDB write concern (defaults to '$default_concern'. See --help for details in header description)" ],
    #"read-concern=s"   => [ \$read_concern,  "MongoDB read  concern (defaults to '$default_concern'. See --help for details in header description)" ],
    #"wtimeout=s"       => [ \$wtimeout,      "Number of milliseconds an operations should wait for w slaves to replicate it (defaults to $default_wtimeout ms)" ],
    "ssl"              => [ \$ssl,           "Enable SSL, MongDB libraries must have been compiled with SSL and server must support it. Experimental" ],
    "sasl"             => [ \$sasl,          "Enable SASL authentication, must be compiled in to the MongoDB perl driver to work. Experimental" ],
    "sasl-mechanism=s" => [ \$sasl_mechanism, "SASL mechanism (default: GSSAPI eg Kerberos on MongoDB Enterprise 2.4+ in which case this should be run from a valid kinit session, alternative PLAIN for LDAP using user/password against MongoDB Enterprise 2.6+ which is sent in plaintext so should be used over SSL). Experimental" ],
    "w|warning=s"      => [ \$warning,       "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "c|critical=s"     => [ \$critical,      "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "precision=i"      => [ \$precision,     "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port database collection user password write-concern read-concern wtimeout ssl sasl sasl-mechanism warning critical precision/;
get_options();

defined($host) or usage "MongoDB host(s) not specified";
my @hosts = split(",", $host);
for(my $i=0; $i < scalar @hosts; $i++){
    $hosts[$i] = validate_hostport(strip($hosts[$i]), "Mongo");
}
my $hosts  = "mongodb://" . join(",", @hosts);
#my $hosts  = join(",", @hosts);
vlog_options "Mongo host list", $hosts;
$database    = validate_database($database, "Mongo");
$collection  = validate_collection($collection, "Mongo");
#unless(($user + $password) / 2 == 0) {
#    usage "--user and --password must both be specified if one of them are";
#}
$user        = validate_user($user)         if defined($user) and defined($password);
$password    = validate_password($password) if defined($password);
grep { $sasl_mechanism eq $_ } qw/GSSAPI PLAIN/ or usage "invalid sasl-mechanism specified, must be either GSSAPI or PLAIN";
grep { $write_concern  eq $_ } @valid_concerns  or usage "invalid write concern given";
grep { $read_concern   eq $_ } @valid_concerns  or usage "invalid read concern given";
vlog_options "write concern", $write_concern;
vlog_options "read concern",  $read_concern;
#validate_int($wtimeout, "wtimeout", 1, 1000000);
vlog_options "ssl",  "enabled" if $ssl;
vlog_options "sasl", "enabled" if $sasl;
vlog_options "sasl-mechanism", $sasl_mechanism if $sasl;
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
vlog_options "document", $document;

$status = "OK";

vlog2;
set_timeout();

my $start_time = time;
my $client;
# TODO: MongoDB module calls die directly, and catching it seems to lead to incorrect error reporting :-/
#try {
    $client = MongoDB::MongoClient->new(
                                        "host"           => $hosts,
                                        #"db_name"        => $database,
                                        "find_master"    => 1,
                                        "w"              => $write_concern,
                                        "r"              => $read_concern,
                                        "j"              => 1,
                                        "timeout"        => int($timeout * 1000 / 4), # connection timeout
                                        "wtimeout"       => $wtimeout,
                                        "query_timeout"  => int($timeout * 1000 / 4),
                                        "ssl"            => $ssl,
                                        "sasl"           => $sasl,
                                        "sasl-mechanism" => $sasl_mechanism,
                                       ) || quit "CRITICAL", "$!";
#};
#catch_quit "failed to connect / find primary MongoDB host";
#quit "CRITICAL", "failed to connect / find primary MongoDB host" if $@;

vlog2 "connection initiated\n";

if($user and $password){
    vlog2 "authenticating against database '$database'";
    #try {
        $client->authenticate($database, $user, $password) || quit "CRITICAL", "failed to authenticate: $!";
    #};
    #catch_quit "failed to authenticate";
}

my $master;
if(defined($client->{'_master'}{'host'})){
    $master = $client->{'_master'}{'host'};
} elsif(defined($client->{'host'})){
    $master = $client->{'host'};
} else {
    quit "CRITICAL", "could not determine master\n";
}
$master =~ s,mongodb://,,;
$master =~ s,:27017,,;
vlog2 "primary is $master\n";

my $db;
my $coll;

# Incorrect error messages are reporting when catching errors, the only way to see accurate messages in testing was to allow the module's die call and wrap the exit code in the library HariSekhonUtils
#try {
    $db = $client->get_database($database)   || quit "CRITICAL", "failed to select database '$database': $!";
#};
#catch_quit "failed to select database '$database'";

#try {
    $coll = $db->get_collection($collection) || quit "CRITICAL", "failed to get collection '$collection': $!";
#};
#catch_quit "failed to get collection '$collection'";

# ============================================================================ #
my $write_start = time;
my $returned_id;
#try {
    $returned_id = $coll->insert(  {
                                    '_id'   => $id,
                                    'value' => $value
                                   } 
                                ) || quit "CRITICAL", "failed to insert document in to database '$database' collection '$collection': $!";
#};
#catch_quit "failed to insert document in to database '$database' collection '$collection'";
my $write_time = sprintf("%0.${precision}f", time - $write_start);
$msg .= "document written in $write_time secs";

unless($returned_id eq $id){
    quit "CRITICAL", "_id returned from insert ('$returned_id') was not as expected ('$id')";
}

vlog2 "wrote   document: $document";

# ============================================================================ #
my $count = 0;

my $read_start = time;
#try {
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
#};
#catch_quit "failed to read document back from collection '$collection' in database '$database'";
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
