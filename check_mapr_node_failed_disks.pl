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

$DESCRIPTION = "Nagios Plugin to check for MapR nodes with failed disks via the MapR Control System REST API

Can optionally specify a specific node or cluster to check all nodes in that cluster.

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

my $url = "/node/list?columns=faileddisks";
$url .= "&cluster=$cluster" if $cluster;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

quit "UNKNOWN", "no data returned, did you specify the correct --cluster? See --list-clusters" unless @data;

my %faileddisks;
my $hostname;
my $found_nodes;
foreach my $node_item (@data){
    $hostname = get_field2($node_item, "hostname");
    if($node){
        next unless ($hostname =~ /^$node(?:\.$domain_regex)?$/i);
        $found_nodes++;
    }
    if(get_field2($node_item, "faileddisks")){
        $faileddisks{$hostname} = 1;
    }
}

if($node){
    quit "UNKNOWN", "node '$node' was not found, did you specify the correct node name? See --list-nodes" unless $found_nodes;
    quit "UNKNOWN", "number of nodes with failed disks is higher than 1 when --node was specified!! This may be indicative of duplicate hostnames among nodes or some other cluster or logic problem. $nagios_plugins_support_msg" if($found_nodes > 1);
}

$msg .= "no " unless %faileddisks;

my $incluster = "";
$incluster = " in cluster '$cluster'" if ($cluster and ($verbose or not $node));
if($node){
    critical if %faileddisks;
    $msg .= "failed disks detected on node '$node'$incluster";
} else {
    my $num_nodes_failed_disks = scalar keys %faileddisks;
    if(%faileddisks){
        $msg .= "$num_nodes_failed_disks ";
    }
    $msg .= "nodes${incluster} with failed disks";
    check_thresholds($num_nodes_failed_disks);
    if(%faileddisks){
        $msg .= ": " . join(", ", sort keys %faileddisks);
    }
    $msg .= " | 'num nodes with failed disks'=$num_nodes_failed_disks";
    msg_perf_thresholds();
}

vlog2;
quit $status, $msg;
