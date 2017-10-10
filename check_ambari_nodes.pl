#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-02 20:31:30 +0000 (Mon, 02 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop node health via Ambari REST API

Checks:

- a given node's state
- all node states, with thresholds for number of unhealthy nodes (default w=0/c=0)
- node health includes state of the host (always) and status of components (optionally disable with --host-state-only)

Tested on Ambari 1.4.4, 1.6.1, 2.1.0, 2.1.2, 2.2.1, 2.5.1 on Hortonworks HDP 2.0, 2.1, 2.2, 2.3, 2.4, 2.6";

$VERSION = "0.8";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(0, 0);

my $host_only;

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options_node,
    "host-state-only"    =>  [ \$host_only,   "Check only the host health (state) and ignore status where refers to components on the host. This keeps it strictly a node health check" ],
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

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

sub lc_healthy($){
    my $str = shift;
    ( $str eq "HEALTHY" ? "healthy" : $str );
}

my $node_state;
my $node_status;
sub check_node_state_status(){
    if($node_state eq "HEALTHY"){
        # ok
    } elsif($node_state eq "UNHEALTHY" or
            $node_state eq "HEARTBEAT_LOST"){
        critical;
    } elsif($node_state eq "WAITING_FOR_HOST_STATUS_UPDATES" or
            $node_state eq "INIT" or
            $node_state eq "UNKNOWN"){
        unknown;
    } else {
        critical;
    }
    unless($host_only){
        if($node_status eq "HEALTHY"){
            # ok
        } elsif($node_status eq "UNHEALTHY"){
            critical;
        } elsif($node_status eq "ALERT"){
            if($node_state eq "HEALTHY"){
                warning;
            } else {
                critical;
            }
        } elsif($node_status eq "UNKNOWN"){
            unknown;
        } else {
            critical;
        }
    }
}

if($node){
    cluster_required();
    node_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node?fields=Hosts/host_state,Hosts/host_status";
    # state appears to be just a string, whereas status is the documented state type HEALTHY/UNHEALTHY/UNKNOWN to check according to API docs. However I've just discovered that state can stay HEALTHY and status UNHEALTHY
    $node_state  = get_field("Hosts.host_state");
    $node_status = get_field("Hosts.host_status");
    $msg = "node '$node' state: " . lc_healthy($node_state) . ", component status: " . lc_healthy($node_status);
    check_node_state_status();
} else {
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts?Hosts/host_state!=HEALTHY" . ( $host_only ? "" : "|Hosts/host_status!=HEALTHY" ) . "&fields=Hosts/host_state,Hosts/host_status";
    my @items = get_field_array("items");
    if(@items){
        my @nodes;
        foreach (@items){
            $node_state  = get_field2($_, "Hosts.host_state");
            $node_status = get_field2($_, "Hosts.host_status");
            push(@nodes, get_field2($_, "Hosts.host_name") . " (state=" . lc_healthy($node_state) . "/status=" . lc_healthy($node_status) . ")");
        }
        my $num_nodes = scalar @nodes;
        plural $num_nodes;
        $msg = "$num_nodes node$plural in non-healthy state";
        check_thresholds($num_nodes);
        $msg .= ": " . join(", ", sort @nodes);
    } else {
        $msg = "all nodes ok - state: healthy" . ( $host_only ? "" : ", components status: healthy");
    }
}

vlog2;
quit $status, $msg;
