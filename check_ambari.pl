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

$DESCRIPTION = "Nagios Plugin to check Hadoop node and service states via Ambari REST API

Checks:

- a given service's state, optionally suppresses alerts in maintenance mode if --maintenance-ok
- a given node's state
- all service states, --maintenance-ok option
- all node states

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
use Data::Dumper;

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $node_metrics        = 0;
my $node_state          = 0;
my $service_metrics     = 0;
my $service_state       = 0;
my $all_service_states  = 0;
my $all_node_states     = 0;

my $maintenance_ok      = 0;

my %metric_results;
my @metrics;
my %metrics_found;
my @metrics_not_found;

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options,
    "list-users"                => [ \$list_users,          "List Ambari users" ],
    "node-state"                => [ \$node_state,          "Check node state of specified node is healthy. Requires --cluster, --node" ],
    "all-node-states"           => [ \$all_node_states,     "Check the state of all nodes in a given cluster" ],
    "service-state"             => [ \$service_state,       "Check service state of specified node+service is healthy. Requires --cluster, --node, --service" ],
    "all-service-states"        => [ \$all_service_states,  "Check all service states for given --cluster" ],
    "maintenance-ok"            => [ \$maintenance_ok,      "Suppress service alerts in maintenance mode" ],
);
splice @usage_order, 10, 0, qw/service-state maintenance-ok node-state all-service-states all-node-states/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;
$service    = validate_ambari_service($service) if $service;
$component  = validate_ambari_component($component) if $component;
$node       = validate_ambari_node($node) if $node;

validate_thresholds();
validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "http://$host:$port$api";

list_ambari_components();

unless($node_state + $all_node_states + $service_state + $all_service_states eq 1){
    usage "must specify exactly one check";
}

sub get_service_state($){
    my $json = shift() || code_error "no hash passed to get_service_state()";
    my $msg;
    my $service_name      = get_field2($json, "ServiceInfo.service_name");
    my $service_state     = get_field2($json, "ServiceInfo.state");
    my $maintenance_state = get_field2($json, "ServiceInfo.maintenance_state");
    $service_name = hadoop_service_name $service_name;
    if($maintenance_ok and $maintenance_state ne "OFF"){
        # suppress alerts if in maintenance mode and --maintenance-ok
        $maintenance_state = lc $maintenance_state;
    } elsif($service_state eq "STARTED" or $service_state eq "INSTALLED"){
        # ok
        $service_state = lc $service_state;
    } elsif($service_state eq "UNKNOWN"){
        unknown;
    } elsif(grep { $service_state eq $_ } qw/STARTING INIT UPGRADING MAINTENANCE INSTALLING/){
        warning;
    } elsif(grep { $service_state eq $_ } qw/INSTALL_FAILED STOPPING UNINSTALLING UNINSTALLED WIPING_OUT/){
        critical;
    } else {
        unknown;
    }
    $msg .= "$service_name state=$service_state";
    if($verbose){
        $msg .= " (maintenance=$maintenance_state)";
    }
    return $msg;
}

if($all_node_states){
    cluster_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts?Hosts/host_state!=HEALTHY|Hosts/host_status!=HEALTHY&fields=Hosts/host_state,Hosts/host_status";
    my @items = get_field_array("items");
    if(@items){
        critical;
        my @nodes;
        foreach (@items){
            push(@nodes, get_field2($_, "Hosts.host_name") . " (state=" . get_field2($_, "Hosts.host_state") . "/status=" . get_field2($_, "Hosts.host_status") . ")");
        }
        plural scalar @nodes;
        $msg = scalar @nodes . " node$plural in non-healthy state: ";
        $msg .= join(", ", sort @nodes);
        $msg =~ s/, $//;
    } else {
        $msg = "no unhealthy nodes";
    }
} elsif($node_state){
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
} elsif($node_metrics){
    cluster_required();
    node_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node";
    # TODO:
} elsif($all_service_states){
    cluster_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/services?fields=ServiceInfo/state,ServiceInfo/maintenance_state";
    my @items = get_field_array("items");
    foreach(@items){
        $msg .= get_service_state($_) . ", ";
    }
    $msg =~ s/, $//;
} elsif($service_state){
    cluster_required();
    service_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service?fields=ServiceInfo/state,ServiceInfo/maintenance_state";
    $msg .= "service " . get_service_state($json);
} elsif($service_metrics){
    cluster_required();
    service_required();
    component_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service/components/$component";
    # TODO:
} else {
    code_error "no check requested, caught late";
}

vlog2;
quit $status, $msg;
