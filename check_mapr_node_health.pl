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

$DESCRIPTION = "Nagios Plugin to check node health of a given MapR Hadoop node or number of unhealthy nodes overall via the MapR Control System REST API

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

# http://doc.mapr.com/display/MapR/node
#
# Node Health:
#
# 0 = Healthy
# 1 = Needs attention
# 2 = Degraded
# 3 = Maintenance
# 4 = Critical
my %node_states = (
    0 => "Healthy",
    1 => "Needs attention",
    2 => "Degraded",
    3 => "Maintenance",
    4 => "Critical",
);

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
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/node/list?columns=health,healthDesc";
$url .= "&cluster=$cluster" if $cluster;
$json = curl_mapr $url, $user, $password;

quit "UNKNOWN", "no node data returned, did you specify the correct --cluster? See --list-clusters" unless @{$json->{"data"}};
my @data = get_field_array("data");

my $node_health_status;
my $health;
my $healthDesc;
my $unhealthy_nodes = 0;
foreach my $item (@data){
    if($node and get_field2($item, "hostname") =~ /^$node(?:\.$domain_regex)?$/){
        $health     = get_field2($item, "health");
        $healthDesc = get_field2($item, "healthDesc");
        if(grep { $health eq $_ } keys %node_states){
            $node_health_status = $node_states{$health};
        } else {
            $node_health_status = "UNKNOWN ($health)";
        }
        last;
    } else {
        $health = get_field2($item, "health");
        unless($node_states{$health} eq "Healthy"){
            $unhealthy_nodes++;
        }
    }
}
if($node){
    defined($node_health_status) or quit "UNKNOWN", "node '$node' not found, did you specify the correct node name? See --list-nodes";
    $msg = "node '$node' health '$node_health_status' description='$healthDesc'";
# Dependent on %node_states
    if($node_health_status eq "Healthy"){
        $status = "OK";
    } elsif(grep { $node_health_status eq $_ } split(",", "Degraded,Needs attention,Maintenance")){
        $status = "WARNING";
    } else {
        $status = "CRITICAL";
    }
} else {
    plural $unhealthy_nodes;
    $msg = "$unhealthy_nodes unhealthy node$plural out of ";
    my $num_nodes = scalar @data;
    plural $num_nodes;
    $msg .= "$num_nodes node$plural total";
    check_thresholds($unhealthy_nodes);
    $msg .= " | unhealthy_nodes=$unhealthy_nodes";
    msg_perf_thresholds();
    $msg .= " total_nodes=$num_nodes";
}

vlog2;
quit $status, $msg;
