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

$VERSION = "0.4";

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

sub get_service_state($$){
    $cluster      = shift;
    $service      = shift;
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service";
    my $state = get_field("ServiceInfo.state");
    # TODO: maintenance_state values need to be documented in the Ambari v1 API docs
    if($maintenance_ok and get_field("ServiceInfo.maintenance_state") ne "OFF"){
        #
    } elsif($state eq "STARTED" or $state eq "INSTALLED"){
        # ok
        $state = lc $state;
    } elsif($state eq "UNKNOWN"){
        unknown;
    } elsif(grep { $state eq $_ } qw/STARTING INIT UPGRADING MAINTENANCE INSTALLING/){
        warning;
    } elsif(grep { $state eq $_ } qw/INSTALL_FAILED STOPPING UNINSTALLING UNINSTALLED WIPING_OUT/){
        critical;
    } else {
        unknown;
    }
    return $state;
}

if($all_node_states){
    cluster_required();
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts?Hosts/host_state!=HEALTHY|Hosts/host_status!=HEALTHY";
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
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node";
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
    my @services = list_services();
    my $service_state;
    $msg = "services - ";
    foreach my $service (@services){
        $service_state = get_service_state($cluster, $service);
        $service = $service_map{$service} if grep { $service eq $_ } keys %service_map;
        $msg .= "$service\[$service_state\], ";
    }
    $msg =~ s/, $//;
} elsif($service_state){
    cluster_required();
    service_required();
    my $state = get_service_state($cluster, $service);
    $service = $service_map{$service} if grep { $service eq $_ } keys %service_map;
    $msg = "service '$service' state '$state'";
    my $maintenance = get_field("ServiceInfo.maintenance_state");
    if($maintenance ne "OFF"){
        warning unless $maintenance_ok;
        $msg .= ", maintenance state '" . lc $maintenance . "'";
    } elsif($verbose){
        $msg .= ", maintenance state '" . lc $maintenance . "'";
    }
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
