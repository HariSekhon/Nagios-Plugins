#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-07-27 22:44:19 +0100 (Sun, 27 Jul 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop config staleness via Ambari REST API

Raises warning for any stale configs found. Lists services and in verbose mode lists unique affected service subcomponents in brackets after each service.

Optionally filter by any combination of node/service/component. Invalid service/component names will prompt you to use the --list switches but an invalid node name will result in a \"500 Server Error\" since that's what Ambari returns (actually causes NPE in Ambari - see Apache Jira AMBARI-6700)

Tested on Ambari 1.6.1, 2.1.0, 2.1.2, 2.2.1, 2.5.1 with Hortonworks HDP 2.1, 2.2. 2.3, 2.4, 2.6";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options_node,
    %ambari_options_service,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;
$service    = validate_ambari_service($service) if $service;
$component  = validate_ambari_component($component) if $component;
$node       = validate_ambari_node($node) if $node;

validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

#$json = curl_ambari "$url_prefix/clusters/$cluster/host_components?HostRoles/stale_configs=true&fields=HostRoles/service_name";
my $url   = "$url_prefix/clusters/$cluster/host_components?";
my %services;
if($node or $service or $component){
    if($node){
        $url .= "HostRoles/host_name=" . $node . "&";
    }
    if($service){
        $url .= "HostRoles/service_name=" . uc $service . "&";
    }
    if($component){
        $url .= "HostRoles/component_name=" . uc $component . "&";
    }
} else {
    $url .= "HostRoles/stale_configs=true&";
}
$url .= "fields=HostRoles/host_name,HostRoles/service_name,HostRoles/component_name,HostRoles/stale_configs";
$json = curl_ambari $url;
my @items = get_field_array("items");
if($node or $service or $component){
    my $msg2 = ""
             . ( $node      ? " node '$node'"            : "" )
             . ( $service   ? " service '$service'"      : "" )
             . ( $component ? " component '$component'"  : "" );
    @items or quit "UNKNOWN", "no matching$msg2 found. Try using the --list-* switches to see what's available to filter on";
    foreach(@items){
        $service = hadoop_service_name(get_field2($_, "HostRoles.service_name"));
        $services{$service}{get_field2($_, "HostRoles.component_name")} = 1;
        if(defined($_->{"HostRoles"}) and
           defined($_->{"HostRoles"}->{"stale_configs"}) and
           $_->{"HostRoles"}->{"stale_configs"}){
            warning;
        }
    }
    if(is_ok()){
        $msg = "no stale config found for$msg2";
    } else {
        $msg = "stale config found for$msg2";
    }
} elsif(@items){
    warning;
    my $service;
    foreach(@items){
        $service = hadoop_service_name(get_field2($_, "HostRoles.service_name"));
        $services{$service}{get_field2($_, "HostRoles.component_name")} = 1;
    }
    $msg = "stale configs found for service";
    plural keys %services;
    $msg .= "$plural: ";
    foreach $service (sort keys %services){
        $msg .= "$service";
        if($verbose){
            $msg .= " (" . lc join(", ", sort keys %{$services{$service}}) . ")";
        }
        $msg .= ", ";
    }
    $msg =~ s/, $//;
} else {
    $msg = "no stale configs";
}

vlog2;
quit $status, $msg;
