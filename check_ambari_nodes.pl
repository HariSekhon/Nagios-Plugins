#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-02 20:31:30 +0000 (Mon, 02 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop node health via Ambari REST API

Checks:

- a given node's state
- all node states, with thresholds for number of unhealthy nodes (default w=0/c=0)

Tested on Hortonworks HDP 2.0 and 2.1";

$VERSION = "0.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname $main::VERSION");

set_threshold_defaults(0, 0);

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options_node,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;
$node       = validate_ambari_node($node) if $node;

validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 1 });
validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "http://$host:$port$api";

list_ambari_components();

cluster_required();
if($node){
    cluster_required();
    node_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node?fields=Hosts/host_state,Hosts/host_status";
    # state appears to be just a string, whereas status is the documented state type HEALTHY/UNHEALTHY/UNKNOWN to check according to API docs. However I've just discovered that state can stay HEALTHY and status UNHEALTHY
    my $node_state  = get_field("Hosts.host_state");
    my $node_status = get_field("Hosts.host_status");
    $msg = "node '$node' state: " . ($node_state eq "HEALTHY" ? "healthy" : $node_state) . ", status: " . ($node_status eq "HEALTHY" ? "healthy" : $node_status);
    if($node_status eq "HEALTHY"){
        # ok
    } elsif($node_status eq "UNHEALTHY"){
        critical;
    } elsif($node_status eq "UNKNOWN"){
        unknown;
    } else {
        critical;
    }
} else {
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts?Hosts/host_state!=HEALTHY|Hosts/host_status!=HEALTHY&fields=Hosts/host_state,Hosts/host_status";
    my @items = get_field_array("items");
    if(@items){
        my @nodes;
        foreach (@items){
            push(@nodes, get_field2($_, "Hosts.host_name") . " (state=" . get_field2($_, "Hosts.host_state") . "/status=" . get_field2($_, "Hosts.host_status") . ")");
        }
        my $num_nodes = scalar @nodes;
        plural $num_nodes;
        $msg = "$num_nodes node$plural in non-healthy state";
        check_thresholds($num_nodes);
        $msg .= ": " . join(", ", sort @nodes);
    } else {
        $msg = "no unhealthy nodes";
    }
}

vlog2;
quit $status, $msg;
