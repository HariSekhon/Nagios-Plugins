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

- a given service's state
- a given node's state
- all service states
- any unhealthy nodes

Tested on Hortonworks HDP 2.0 and 2.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON 'decode_json';
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $protocol   = "http";
set_port_default(8080);
my $ssl_port   = 8443;

my $cluster;
my $service;
my $component;
my $node;
my $metrics;
my $url;

my $node_metrics        = 0;
my $node_state          = 0;
my $list_nodes          = 0;
my $list_clusters       = 0;
my $list_svc_components = 0;
my $list_svc_nodes      = 0;
my $list_svcs           = 0;
my $list_svcs_nodes     = 0;
my $service_metrics     = 0;
my $service_state       = 0;
my $all_service_states  = 0;
my $unhealthy_nodes     = 0;

my %metric_results;
my @metrics;
my %metrics_found;
my @metrics_not_found;

env_creds("Ambari");

# Ambari REST API:
#
# /clusters                                                 - list clusters + version HDP-1.2.0
# /clusters/$cluster                                        - list svcs + nodes in cluster
# /clusters/$cluster/services                               - list svcs
# /clusters/$cluster/services/$service                      - service state + components
# /clusters/$cluster/services/$service/components/DATANODE  - state, nodes, TODO: metrics
# /clusters/$cluster/hosts                                  - list nodes
# /clusters/$cluster/host/$node                             - host_state, disks, rack, TODO: metrics
# /clusters/$cluster/host/$node/host_components             - list host components
# /clusters/$cluster/host/$node/host_components/DATANODE    - state + metrics

%options = (
    %hostoptions,
    %useroptions,
    #%thresholdoptions,
    "list-clusters"             => [ \$list_clusters,       "Lists all the clusters managed by the Ambari server" ],
    "list-nodes"                => [ \$list_nodes,          "Lists all the nodes managed by the Ambari server for given --cluster (includes Ambari server itself)" ],
    "list-services"             => [ \$list_svcs,           "Lists all services in the given --cluster" ],
    "list-service-components"   => [ \$list_svc_components, "Lists all components of a given service. Requires --cluster, --service" ],
    "list-service-nodes"        => [ \$list_svc_nodes,      "Lists all nodes for a given service. Requires --cluster, --service, --component" ],
    "C|cluster=s"               => [ \$cluster,             "Cluster Name as shown in Ambari (eg. \"MyCluster\")" ],
    "S|service=s"               => [ \$service,             "Service Name as shown in Ambari (eg. HDFS, HBASE, usually capitalized). Requires --cluster" ],
    "N|node=s"                  => [ \$node,                "Specify FQDN of node to check, use in conjunction with other switches such as --node-state" ],
    "O|component=s"             => [ \$component,           "Service component to check (eg. DATANODE)" ],
    "node-state"                => [ \$node_state,          "Check node state of specified node is healthy. Requires --cluster, --node" ],
    "unhealthy-nodes"           => [ \$unhealthy_nodes,     "Check for any unhealthy nodes" ],
    "service-state"             => [ \$service_state,       "Check service state of specified node+service is healthy. Requires --cluster, --node, --service" ],
    "all-service-states"        => [ \$all_service_states,  "Check all service states for given --cluster" ],
    # TODO:
    #"node-metrics"              => [ \$node_metrics,        "Check node metrics for specified cluster node. Requires --cluster/--node" ],
    #"service-metrics"           => [ \$service_metrics,     "Check service metrics for specified cluster service. Requires --cluster/--service" ],
    %tlsoptions
);
splice @usage_order, 6, 0, qw/cluster service node component list-clusters list-services list-nodes list-service-components list-service-nodes node-state service-state all-service-states service-metrics unhealthy-nodes/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$service    = uc $service   if $service;
$component  = uc $component if $component;
unless($list_clusters + $list_nodes + $list_svcs + $list_svc_components + $node_state + $service_state + $all_service_states + $service_metrics + $unhealthy_nodes + $list_svc_nodes eq 1){
    usage "must specify exactly one check";
}

validate_thresholds();
validate_tls();

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port/api/v1";
my $json;

sub curl_ambari($){
    my $url = shift;
    # { status: 404, message: blah } handled in curl() in lib
    my $content = curl $url, "Ambari", $user, $password;

    my $json;
    try{
        $json = decode_json $content;
    };
    catch{
        quit "invalid json returned by Ambari at '$url_prefix', did you try to connect to the SSL port without --tls?";
    };
    return $json;
}

my %service_map = (
    "GANGLIA"       => "Ganglia",
    "HBASE"         => "HBase",
    "HCATALOG"      => "HCatalog",
    "HDFS"          => "HDFS",
    "HIVE"          => "Hive",
    "MAPREDUCE"     => "MapReduce",
    "MAPREDUCE2"    => "MapReduce2",
    "NAGIOS"        => "Nagios",
    "OOZIE"         => "Oozie",
    "WEBHCAT"       => "WebHCat",
    "YARN"          => "Yarn",
    "ZOOKEEPER"     => "ZooKeeper",
);

sub list_services($){
    my $cluster = shift;
    $json = curl_ambari "$url_prefix/clusters/$cluster/services";
    unless(defined($json->{"items"})){
        code_error "cluster services not returned in expected format from Ambari. $nagios_plugins_support_msg_api";
    }
    my @services;
    foreach my $item (@{$json->{"items"}}){
        unless(defined($item->{"ServiceInfo"}) and defined($item->{"ServiceInfo"}{"cluster_name"}) and defined($item->{"ServiceInfo"}{"service_name"})){
            code_error "cluster services not returned in expected format from Ambari. $nagios_plugins_support_msg_api";
        }
        push(@services, $item->{"ServiceInfo"}{"service_name"});
        vlog3 sprintf "%-19s %s", $item->{"ServiceInfo"}{"cluster_name"}, $item->{"ServiceInfo"}{"service_name"};
    }
    return sort @services;
}

sub get_service_state($$){
    $cluster = shift;
    $service = shift;
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service";
    defined($json->{"ServiceInfo"}{"state"}) or quit "UNKNOWN", "ServiceInfo state field not found for cluster '$cluster' service '$service'. $nagios_plugins_support_msg_api";
    my $state = $json->{"ServiceInfo"}{"state"};
    if($state eq "STARTED" or $state eq "INSTALLED"){
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

if($list_clusters){
    my %clusters;
    $json = curl_ambari "$url_prefix/clusters";
    unless(defined($json->{"items"}) and isArray($json->{"items"})){
        code_error "cluster list not returned properly from Ambari. API may have changed. $nagios_plugins_support_msg";
    }
    my $num_clusters = scalar(@{$json->{"items"}});
    quit "CRITICAL", "no clusters managed by Ambari?!" unless $num_clusters;
    plural $num_clusters;
    $msg = "$num_clusters cluster$plural - ";
    foreach(@{$json->{"items"}}){
        unless(defined($_->{"Clusters"}) and
                isHash($_->{"Clusters"}) and
               defined($_->{"Clusters"}->{"cluster_name"}) and
               defined($_->{"Clusters"}->{"version"})
               ){
            code_error "cluster list not returned in expected format from Ambari. API may have changed. $nagios_plugins_support_msg";
        }
        vlog2   sprintf("%-19s %s\n", $_->{"Clusters"}->{"cluster_name"}, $_->{"Clusters"}->{"version"});
        $msg .= sprintf("%s (%s), ",  $_->{"Clusters"}->{"cluster_name"}, $_->{"Clusters"}->{"version"});
    }
    $msg =~ s/, $//;
} elsif($list_nodes){
    $cluster or usage "--cluster required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts";
    my $num_nodes = scalar @{$json->{"items"}};
    my @nodes;
    plural $num_nodes;
    $msg = "$num_nodes node$plural in cluster $cluster - ";
    foreach my $item (@{$json->{"items"}}){
        defined($item->{"Hosts"}{"host_name"}) or quit "UNKNOWN", "host_name field not found. $nagios_plugins_support_msg_api";
        vlog2 sprintf("node %s", $item->{"Hosts"}{"host_name"});
        push(@nodes, $item->{"Hosts"}{"host_name"});
    }
    $msg .= join(", ", sort @nodes);
} elsif($node_state){
    $cluster or usage "--cluster required";
    $node    or usage "--node required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node";
    defined($json->{"Hosts"}{"host_state"}) or quit "UNKNOWN", "host_state field not found. $nagios_plugins_support_msg_api";
    defined($json->{"Hosts"}{"host_status"}) or quit "UNKNOWN", "host_status field not found. $nagios_plugins_support_msg_api";
    my $node_state = $json->{"Hosts"}{"host_status"};
    $msg = "node '$node' state: " . $json->{"Hosts"}{"host_state"};
    if($node_state eq "HEALTHY"){
        # ok
    } elsif($node_state eq "UNHEALTHY"){
        critical;
    } elsif($node_state eq "UNKNOWN"){
        unknown;
    } else {
        critical;
    }
} elsif($unhealthy_nodes){
    $cluster or usage "--cluster required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts?Hosts/host_status!=HEALTHY";
    defined($json->{"items"}) or quit "UNKNOWN", "items not found. $nagios_plugins_support_msg_api";
    if(@{$json->{"items"}}){
        critical;
        my @nodes;
        foreach my $item (@{$json->{"items"}}){
            defined($item->{"Hosts"}{"host_name"})  or quit "UNKNOWN", "host_name not found for host item returned. $nagios_plugins_support_msg_api";
            defined($item->{"Hosts"}{"host_status"}) or quit "UNKNOWN", "host_status not found for host item returned. $nagios_plugins_support_msg_api";
            push(@nodes, $item->{"Hosts"}{"host_name"} . " (" . $item->{"Hosts"}{"host_status"} . ")");
        }
        plural scalar @nodes;
        $msg = scalar @nodes . " node$plural in non-healthy state: ";
        $msg .= join(", ", sort @nodes);
        $msg =~ s/, $//;
    } else {
        $msg = "no unhealthy nodes";
    }
} elsif($node_metrics){
    $cluster or usage "--cluster required";
    $node    or usage "--node required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/hosts/$node";
    # TODO:
} elsif($list_svcs){
    $cluster or usage "--cluster required";
    my @services = list_services($cluster);
    $msg = "services: " . join(", ", @services);
} elsif($service_state){
    $cluster or usage "--cluster required";
    $service or usage "--service required";
    my $state = get_service_state($cluster, $service);
    $service = $service_map{$service} if grep { $service eq $_ } keys %service_map;
    $msg = "service '$service' state '$state'";
} elsif($all_service_states){
    $cluster or usage "--cluster required";
    my @services = list_services($cluster);
    my $service_state;
    $msg = "services - "; 
    foreach my $service (@services){
        $service_state = get_service_state($cluster, $service);
        $service = $service_map{$service} if grep { $service eq $_ } keys %service_map;
        $msg .= "$service\[$service_state\], ";
    }
    $msg =~ s/, $//;
} elsif($list_svc_components){
    $cluster or usage "--cluster required";
    $service or usage "--service required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service";
    defined($json->{"components"}) or quit "UNKNOWN", "components not found. $nagios_plugins_support_msg_api";
    my @components;
    foreach my $component (@{$json->{"components"}}){
        defined($component->{"ServiceComponentInfo"}{"component_name"}) or quit "UNKNOWN", "component_name not found for service '$service'. $nagios_plugins_support_msg_api";
        push(@components, $component->{"ServiceComponentInfo"}{"component_name"});
    }
    $msg = "service '$service' components: " . join(", ", sort @components);
} elsif($list_svc_nodes){
    $cluster   or usage "--cluster required";
    $service   or usage "--service required";
    $component or usage "--component required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service/components/$component";
    defined($json->{"host_components"}) or quit "UNKNONWN", "host_components field not found for service '$service' component '$component'. $nagios_plugins_support_msg_api";
    my @nodes;
    foreach my $item (@{$json->{"host_components"}}){
        defined($item->{"HostRoles"}{"host_name"}) or quit "UNKNOWN", "host_name field not found for service '$service' component '$component'. $nagios_plugins_support_msg_api";
        push(@nodes, $item->{"HostRoles"}{"host_name"});
    }
    $msg = "service '$service' component '$component' nodes: " . join(", ", @nodes);
} elsif($service_metrics){
    $cluster   or usage "--cluster required";
    $service   or usage "--service required";
    $component or usage "--component required";
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service/components/$component";
    # TODO:
} else {
    code_error "no check requested, caught late";
}

vlog2;
quit $status, $msg;
