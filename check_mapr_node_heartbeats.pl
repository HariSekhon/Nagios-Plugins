#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check MapR node heartbeats to CLDB via the MapR Control System REST API

By defaults checks all nodes for heartbeat age > 3 (--heartbeat-max). Can restrict by --cluster.

Alternatively check a single --node heartbeat age against the warning/critical thresholds.

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(0, 1);

my $heartbeat_max_default = 3;
my $heartbeat_max = $heartbeat_max_default;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_node,
    "heartbeat-max=s"   => [ \$heartbeat_max,  "Hearbeat threshold in secs for all nodes when not specifying --nodes (default: $heartbeat_max_default). Warning/Critical thresholds apply to the number of failing nodes in this case" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/cluster node heartbeat-max list-clusters list-nodes/;

get_options();

validate_mapr_options();
list_clusters();
list_nodes();
$cluster = validate_cluster $cluster if $cluster;
$node    = validate_host($node, "node") if $node;
validate_float($heartbeat_max, "heartbeat max", 0, 100);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/node/list?columns=fs-heartbeat";
$url .= "&cluster=$cluster" if $cluster;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

quit "UNKNOWN", "no node data returned, did you specify the correct --cluster? See --list-clusters" unless @data;

my %fs_heartbeat;
my $hostname;
foreach my $node_item (@data){
    $hostname = get_field2($node_item, "hostname");
    if($node){
        if($hostname =~ /^$node(?:\.$domain_regex)?$/){
            $fs_heartbeat{$node} = get_field2_float($node_item, "fs-heartbeat");
        }
    } else {
        $fs_heartbeat{$hostname} = get_field2_float($node_item, "fs-heartbeat");
    }
}
if($node){
    unless(%fs_heartbeat and defined($fs_heartbeat{$node})){
        quit "UNKNOWN", "node '$node' heartbeat not found. Did you specify the correct node --node? See --list-nodes";
    }
    $msg .= "node '$node' heartbeat last detected $fs_heartbeat{$node} secs ago";
    check_thresholds($fs_heartbeat{$node});
    $msg .= " | heartbeat_age=$fs_heartbeat{$node}s";
    msg_perf_thresholds();
} else {
    unless(%fs_heartbeat){
        quit "UNKNOWN", "no nodes heartbeats found. $nagios_plugins_support_msg_api";
    }
    my $bad_heartbeats = 0;
    my $node_count = get_field("total");
    foreach(sort keys %fs_heartbeat){
        $bad_heartbeats++ if $fs_heartbeat{$_} > $heartbeat_max;
    }
    plural $bad_heartbeats;
    $msg .= "$bad_heartbeats node$plural with heartbeats > $heartbeat_max secs";
    check_thresholds($bad_heartbeats);
    plural $node_count;
    $msg .= " out of $node_count node$plural";
    $msg .= " in cluster '$cluster'" if $cluster;
    $msg .= " | 'num nodes with heartbeats > $heartbeat_max secs'=$bad_heartbeats";
    msg_perf_thresholds();
}

vlog2;
quit $status, $msg;
