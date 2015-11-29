#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/data_modeling.html#method-get-keyspaces

$DESCRIPTION = "Nagios Plugin to check Cassandra's replication factor and replica placement strategy for a given cluster and keyspace via the DataStax OpsCenter Rest API

Also checks durable writes are enabled by default, configurable to expect durable writes to be disabled instead.

Tested on DataStax OpsCenter 3.2.2 and 5.0.0";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use Data::Dumper;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expect_no_durable_writes;
my $expected_replication_factor;
my $expected_replication_strategy;

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    %keyspaceoption,
    "F|replication-factor=s"    =>  [ \$expected_replication_factor,    "Replication factor to expect (integer, optional)" ],
    "S|replication-strategy=s"  =>  [ \$expected_replication_strategy,  "Replication strategy to expect (string of class name eg. 'org.apache.cassandra.locator.SimpleStrategy', optional)" ],
    "W|no-durable-writes"       =>  [ \$expect_no_durable_writes,       "Expect non-durable writes (default is to expect durable writes)" ],
);
splice @usage_order, 6, 0, qw/cluster keyspace replication-factor replication-strategy no-durable-writes list-clusters list-keyspaces/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
validate_keyspace();
$expected_replication_factor = validate_int($expected_replication_factor, "expected replication factor", 1) if defined($expected_replication_factor);

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();
list_keyspaces();

$json = curl_opscenter "$cluster/keyspaces/$keyspace";
vlog3 Dumper($json);

my $replica_placement_strategy = get_field("replica_placement_strategy");
my $replication_factor         = get_field_int("strategy_options.replication_factor");
my $durable_writes             = get_field("durable_writes");

$msg = "cluster '$cluster' keyspace '$keyspace' replication factor: '$replication_factor'";
if(defined($expected_replication_factor) and $replication_factor != $expected_replication_factor){
    critical;
    $msg .= " (expected: $expected_replication_factor)";
}

$msg .= ", strategy: '$replica_placement_strategy'";
if(defined($expected_replication_strategy) and $replica_placement_strategy ne $expected_replication_strategy){
    critical;
    $msg .= " (expected: $expected_replication_strategy)";
}

$msg .= ", durable writes: " . ( $durable_writes ? "true" : "false" );
if($expect_no_durable_writes and $durable_writes){
    critical;
    $msg .= " (expected: false)";
} elsif(not $durable_writes){
    critical;
    $msg .= " (expected: true)";
}

vlog2;
quit $status, $msg;
