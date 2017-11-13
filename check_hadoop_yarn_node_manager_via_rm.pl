#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the state of a given Hadoop Yarn Node Manager via the Resource Manager's REST API

Checks the given Node Manager is in the 'running' state from the point of view of the Resource Manager.

Thresholds apply to lag time in seconds for last health report from the Node Manager.

See also:

- check_hadoop_yarn_node_manager.pl
- check_hadoop_yarn_node_managers.pl (aggregate view of the number of healthy / unhealthy Node Managers)

Specifying --node-id results in a more efficient query of the Resource Manager. Use this instead of --node for large clusters otherwise it ends up enumerating all the node managers.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.2";

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

# From Hortonworks distribution this defaults to 45454
my $node_port_default = 45454;

my $node;
my $node_id;
my $list_nodes;

%options = (
    %hostoptions,
    "I|node-id=s"   =>  [ \$node_id,    "Node ID to query (hostname:port, port defaults to $node_port_default if not specified)" ],
    "N|node=s"      =>  [ \$node,       "Node Manager hostname to check (--node-id preferred for efficiency, see --help description)" ],
    "list-nodes"    =>  [ \$list_nodes, "List node manager hostnames and ids" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/node-id node list-nodes/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
unless($list_nodes){
    $node or $node_id or usage "node hostname not specified. Use --list-nodes as convenience to find node hostname";
}
$node and $node_id and usage "cannot specify both --node and --node-id";
if($node_id){
    $node_id =~ /:\d+$/ or $node_id .= ":$node_port_default";
    $node_id = validate_hostport($node_id, "node id");
} elsif($node) {
    $node = validate_host($node, "node");
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster/nodes";
unless($list_nodes){
    $url .= "/$node_id" if $node_id;
}

sub rm_error_handler($){
    my $response = shift;
    my $content  = $response->content;
    my $json;
    my $additional_information = "";
    my $err = "";
    if($json = isJson($content)){
        if(defined($json->{"RemoteException"}{"javaClassName"})){
            $err .= $json->{"RemoteException"}{"javaClassName"} . ": ";
        } elsif(defined($json->{"RemoteException"}{"exception"})){
            $err .= $json->{"RemoteException"}{"exception"} . ": ";
        }
        if(defined($json->{"RemoteException"}{"message"})){
            $err .= $json->{"RemoteException"}{"message"};
        }
        $err = ". $err" if $err;
    }
    if($err or $response->code ne "200"){
        quit "CRITICAL", $response->code . " " . $response->message . $err;
    }
    unless($content){
        quit "CRITICAL", "blank content returned by Yarn Resource Manager";
    }
}

my $content = curl $url, undef, undef, undef, \&rm_error_handler;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my @nodes;
if($list_nodes or $node){
    @nodes = get_field_array("nodes.node");
}

if($list_nodes){
    print "Node Manager hostnames:\n\n";
    foreach(@nodes){
        printf("%s\t(id: %s)\n", get_field2($_, "nodeHostName"), get_field2($_, "id") );
    }
    exit $ERRORS{"UNKNOWN"};
}

my $node_ref;
if($node_id){
    $node_ref = get_field("node");
} else {
    my $found;
    foreach(my $i = 0; $i < scalar @nodes; $i++){
        next unless get_field2($nodes[$i], "nodeHostName") eq $node;
        $node_ref = $nodes[$i];
        $found++;
        last;
    }
    $found or quit "UNKNOWN", "node manager '$node' not found. Check you've specified the right hostname by using the --list-nodes switch. If you're sure you've specified the right hostname then $nagios_plugins_support_msg_api";
}

my $availMemoryMB    = get_field2_float($node_ref, "availMemoryMB");
my $healthReport     = get_field2($node_ref, "healthReport");
# appears to not be returned on 2.4 despite what this says http://hadoop.apache.org/docs/r2.4.0/hadoop-yarn/hadoop-yarn-site/ResourceManagerRest.html
#my $healthState      = get_field2($node_ref, "healthState");
my $lastHealthUpdate = get_field2_float($node_ref, "lastHealthUpdate");
my $numContainers    = get_field2_int($node_ref, "numContainers");
my $rack             = get_field2($node_ref, "rack");
my $state            = get_field2($node_ref, "state");
if($node_id){
    $node = get_field2($node_ref, "nodeHostName");
}

my $lag = sprintf("%d", time - $lastHealthUpdate/1000);

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
