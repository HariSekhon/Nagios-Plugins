#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-17 22:35:14 +0000 (Tue, 17 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given Mongod is the Master/Primary of a MongoDB Replica Set

Tested on MongoDB 2.4.8, 2.6.1, 3.2.1";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MongoDB;
use MongoDB::MongoClient;
use Data::Dumper;

my $expected_master;

%options = (
    "H|host=s"              => [ \$host,          "MongoDB host(s) to connect to (should be from same replica set), comma separated, with optional :<port> suffixes. Tries hosts in given order from left to right (\$MONGODB_HOST, \$HOST)" ],
    %useroptions,
    "e|expected-master=s"   => [ \$expected_master, "Checks the master against a specific regex rather than the specified --host. Required if specifying more than one --host" ],
    %mongo_sasl_options,
);
splice @usage_order, 6, 0, "expected-master";

get_options();

$hosts    = validate_mongo_hosts($host);
$user     = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
if(scalar @hosts > 1){
    $expected_master or usage "must specify --expected-master if specifying more than one host to connect to in the replica set";
}
$expected_master = validate_regex($expected_master) if $expected_master;
validate_mongo_sasl();

vlog2;
set_timeout();

$status = "OK";

my $client = connect_mongo($hosts);

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

defined($ismaster->{"setName"}) or quit "CRITICAL", "not part of a MongoDB Replica Set. Make sure you're connected to MongoD replSet instance(s), not MongoS or standalone MongoD";
defined($ismaster->{"primary"}) or quit "CRITICAL", "no 'primary' found (election in progress or lack of quorum?)";
defined($ismaster->{"me"})      or quit "UNKNOWN",  "failed to find 'me' field in 'ismaster' output. $nagios_plugins_support_msg_api";

my $master  = $ismaster->{"primary"};
my $me      = $ismaster->{"me"};
my $setName = $ismaster->{"setName"};

$master or quit "CRITICAL", "primary field empty!";
vlog2 "found replica set primary: '$master'\n";

$msg = "master is '$master'";

if($expected_master){
    check_regex($master, $expected_master);
} else {
    if($master ne $me){
        critical;
        $msg .= " (expected connected host '$me')";
    }
}

$msg .= " for replica set '$setName'";

quit $status, $msg;
