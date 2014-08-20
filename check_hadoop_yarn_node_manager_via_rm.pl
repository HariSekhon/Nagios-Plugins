#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the state of a given Hadoop Yarn Node Manager via the Resource Manager's REST API

Checks the given Node Manager is in the 'running' state from the point of view of the Resource Manager.

Thresholds apply to lag time in seconds for last health report from the Node Manager.

See also:

- check_hadoop_yarn_node_manager.pl (more efficient)
- check_hadoop_yarn_node_managers.pl (aggregate view of the number of healthy / unhealthy Node Managers)

Caveat this will internally return a complete list of information on all node managers from the Resource Manager in order to find the right one. This is not very efficient for very large clusters. The alternative would need to know the node id which itself would require an enumeration of the node managers to find. Therefore this is done on a single pass of the Node Managers output. It's more efficient and scales better to query the node manager directly using check_hadoop_yarn_node_manager.pl

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8088);
set_threshold_defaults(150, 300);

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Yarn Resource Manager");

my $node;
my $list_nodes;

%options = (
    %hostoptions,
    "N|node=s"      =>  [ \$node,       "Node Manager hostname to check" ],
    "list-nodes"    =>  [ \$list_nodes, "List node manager hostnames" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/node list-nodes/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
unless($list_nodes){
    $node or usage "node hostname not specified. Use --list-nodes as convenience to find node hostname";
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster/nodes";
# Unfortunately this requires the node id (hostname:\d+) which would require the full enumeration of nodes to find anyway, may as well leave it as one pass iteration, not great but all the REST API currently allows me to do
#$url .= "/$node" unless($list_nodes);

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my @nodes = get_field_array("nodes.node");

if($list_nodes){
    print "Node Manager hostnames:\n\n";
    foreach(@nodes){
        print get_field2($_, "nodeHostName") . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $found;
my $availMemoryMB;
my $healthReport;
my $healthState;
my $lastHealthUpdate;
my $numContainers;
my $rack;
my $state;
foreach(@nodes){
    next unless get_field2($_, "nodeHostName") eq $node;
    $availMemoryMB    = get_field2_float($_, "availMemoryMB");
    $healthReport     = get_field2($_, "healthReport");
    # appears to not be returned on 2.4 despite what this says http://hadoop.apache.org/docs/r2.4.0/hadoop-yarn/hadoop-yarn-site/ResourceManagerRest.html
    #$healthState      = get_field2($_, "healthState");
    $lastHealthUpdate = get_field2_float($_, "lastHealthUpdate");
    $numContainers    = get_field2_int($_, "numContainers");
    $rack             = get_field2($_, "rack");
    $state            = get_field2($_, "state");
    $found++;
    last;
}
$found or quit "UNKNOWN", "node manager '$node' not found. Check you've specified the right hostname by using the --list-nodes switch. If you're sure you've specified the right hostname then $nagios_plugins_support_msg_api";

my $lag = sprintf("%d", time - $lastHealthUpdate/1000);
#vlog2 "lag is $lag secs";

# For some reason the content of this is blank when API docs say it should be 'Healthy', but my nodes work so this isn't critical
$healthReport = "<blank>" unless $healthReport;

if($state eq "RUNNING"){
    $state = "running";
} else { 
    critical;
}
$msg = "node $node state = '$state', healthReport = '$healthReport', $lag secs since last health report";
check_thresholds($lag);
$msg .= sprintf(", num containers = %d, available memory = %s", $numContainers, human_units($availMemoryMB * 1024 * 1024));
$msg .= ", rack = $rack" if $verbose;
$msg .= sprintf(" | 'health report status lag'=%ds%s 'num containers'=%d 'available memory'=%dMB", $lag, msg_perf_thresholds(1), $numContainers, $availMemoryMB);

quit $status, $msg;
