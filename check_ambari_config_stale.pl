#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-07-27 22:44:19 +0100 (Sun, 27 Jul 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop config staleness via Ambari REST API

Raises warning for any stale configs found. Lists services and in verbose mode lists unique affected service subcomponents in brackets after each service.

Tested on Ambari 1.6.1 with Hortonworks HDP 2.1";

$VERSION = "0.2";

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

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;

validate_thresholds();
validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "http://$host:$port$api";

list_ambari_components();

cluster_required();
# TODO: this needs to be documented better in the github v1 API doc
$json = curl_ambari "$url_prefix/clusters/$cluster/host_components?HostRoles/stale_configs=true&fields=HostRoles/service_name";
my @items = get_field_array("items");
if(@items){
    warning;
    $msg = "stale configs found for service";
    my %services;
    my $service;
    foreach(@items){
        $service = hadoop_service_name(get_field2($_, "HostRoles.service_name"));
        $services{$service}{get_field2($_, "HostRoles.component_name")} = 1;
    }
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
