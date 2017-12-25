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

$DESCRIPTION = "Nagios Plugin to check for MapR nodes with alarms via the MapR Control System REST API

Can optionally specifying a cluster to check for all nodes in that cluster with alarms managed by the MapR Control System by default.

Can also optionally specify a node to check for alarms only on that specific node.

Thresholds apply to the number of nodes with alarms.

Caveat: if specifying a cluster make sure to specify the correct cluster name as otherwise no node alarms will be found. This is a limitation of the behaviour of the MCS API to return no results (indistinguishable from a valid cluster with no alarms) instead of raising an error for an invalid cluster name. See --list-clusters. The same issue exists with specifying a node, although that's a limitation of iterating over the results to search for a node match.

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

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_node,
    %thresholdoptions,
);

get_options();

validate_mapr_options();
list_clusters();
list_nodes();
$cluster = validate_cluster $cluster if $cluster;
$node    = validate_host($node, "node") if $node;
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/node/list?alarmednodes=1";
$url .= "&cluster=$cluster" if $cluster;
$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

#quit "UNKNOWN", "no node data returned, did you specify the correct --cluster? See --list-clusters" unless @data;

my @nodes_with_alarms;

foreach(@data){
    push(@nodes_with_alarms, get_field2($_, "hostname"));
}
if($node){
    if(grep { $_ =~ /^$node(?:\.$domain_regex)?$/ } @nodes_with_alarms){
        $msg = "node '$node' alarms triggered, please investigate in MapR Control System";
    } else {
        $msg = "node '$node' has no alarms";
    }
} else {
    my $node_alarm_count = scalar @nodes_with_alarms;
    if($node_alarm_count){
        plural $node_alarm_count;
        $msg = "$node_alarm_count MapR node$plural with alarms: " . join(", ", sort @nodes_with_alarms);
    } else {
        $msg = "no MapR nodes with alarms";
    }
    $msg .= " for cluster '$cluster'" if $cluster;
    check_thresholds($node_alarm_count);
    $msg .= " | node_alarms=$node_alarm_count";
    msg_perf_thresholds();
}

vlog2;
quit $status, $msg;
