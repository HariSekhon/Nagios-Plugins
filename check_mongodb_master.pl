#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-17 22:35:14 +0000 (Tue, 17 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given Mongod is the Master of a Replica Set";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use MongoDB::MongoClient;

env_creds("MongoDB");

my $expected_master;

my $ssl               = 0;
my $sasl              = 0;
my $sasl_mechanism    = "GSSAPI";

%options = (
    "H|host=s"              => [ \$host,          "MongoDB host(s) to connect to (should be from same replica set), comma separated, with optional :<port> suffixes. Tries hosts in given order from left to right to find Primary for write. Specifying any one host is sufficient as the rest will be auto-determined to find the primary (\$MONGODB_HOST, \$HOST)" ],
    %useroptions,
    "e|expected-master=s"   => [ \$expected_master, "Checks the master against a specific regex rather than the specified --host. Required if specifying more than one --host" ],
    "ssl"                   => [ \$ssl,             "Enable SSL, MongDB libraries must have been compiled with SSL and server must support it. Experimental" ],
    "sasl"                  => [ \$sasl,            "Enable SASL authentication, must be compiled in to the MongoDB perl driver to work. Experimental" ],
    "sasl-mechanism=s"      => [ \$sasl_mechanism,  "SASL mechanism (default: GSSAPI eg Kerberos on MongoDB Enterprise 2.4+ in which case this should be run from a valid kinit session, alternative PLAIN for LDAP using user/password against MongoDB Enterprise 2.6+ which is sent in plaintext so should be used over SSL). Experimental" ],
);

@usage_order = qw/host port user password expected-master ssl sasl sasl-mechanism/;
get_options();

defined($host) or usage "MongoDB host(s) not specified";
my @hosts = split(",", $host);
for(my $i=0; $i < scalar @hosts; $i++){
    $hosts[$i] = validate_hostport(strip($hosts[$i]), "Mongo");
}
my $hosts  = "mongodb://" . join(",", @hosts);
#my $hosts  = join(",", @hosts);
vlog_options "Mongo host list", $hosts;
if(scalar @hosts > 1){
    $expected_master or usage "must specify --expected-master if specifying more than one host to connect to in the replica set";
}
$user       = validate_user($user);
$password   = validate_password($password) if $password;
$expected_master = validate_regex($expected_master) if $expected_master;
grep { $sasl_mechanism eq $_ } qw/GSSAPI PLAIN/ or usage "invalid sasl-mechanism specified, must be either GSSAPI or PLAIN";
vlog_options "ssl",  "enabled" if $ssl;
vlog_options "sasl", "enabled" if $sasl;
vlog_options "sasl-mechanism", $sasl_mechanism if $sasl;

vlog2;
set_timeout();

$status = "OK";

my $client;
try {
    $client = MongoDB::MongoClient->new(
                                        "host"           => $hosts,
                                        # hangs when giving only nodes of a replica set that aren't the Primary
                                        #"find_master"    => 1,
                                        "timeout"        => int($timeout * 1000 / 4), # connection timeout
                                        #"wtimeout"       => $wtimeout,
                                        "query_timeout"  => int($timeout * 1000 / 4),
                                        "ssl"            => $ssl,
                                        "sasl"           => $sasl,
                                        "sasl-mechanism" => $sasl_mechanism,
                                       ) || quit "CRITICAL", "$!";
};
catch_quit "failed to connect to MongoDB host '$hosts'";

vlog2 "connection initiated to $host\n";

my @dbs = $client->database_names;
@dbs or quit "UNKNOWN", "no databases found on Mongod server, cannot call ismaster";
my $database = $dbs[0];
my $db;
try {
    $db = $client->get_database($database)   || quit "CRITICAL", "failed to select database '$database': $!";
};
catch_quit "failed to select database '$database'";

vlog2 "selected first database '$database'";

my $ismaster = $db->run_command({"ismaster" => 1});

vlog3(Dumper($ismaster));

defined($ismaster->{"primary"}) or quit "UNKNOWN", "failed to find 'primary' - not part of a Replica Set?";
defined($ismaster->{"me"})      or quit "UNKNOWN", "failed to find 'me' field in ismaster output. API may have changed. $nagios_plugins_support_msg";

vlog2 "got master\n";

my $master = $ismaster->{"primary"};
my $me     = $ismaster->{"me"};

$msg = "master is '$master'";

if($expected_master){
    if($master =~ /$expected_master/){
        $msg .= " (expected regex: '$expected_master')" if $verbose;
    } else {
        critical;
        $msg .= " (expected regex: '$expected_master')";
    }
} else {
    if($master ne $me){
        critical;
        $msg .= " (this host is '$me')";
    }
}

quit $status, $msg;
