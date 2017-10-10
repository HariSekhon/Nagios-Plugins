#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-11-26 19:44:32 +0000 (Thu, 26 Nov 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check an Ambari managed Cluster's desired service configurations are compatible with the current cluster and current stack via Ambari REST API

Tested on Ambari 2.1.0, 2.1.2, 2.2.1, 2.5.1 on Hortonworks HDP 2.2, 2.3, 2.4, 2.6";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected;

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

validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

$msg = "Ambari cluster '$cluster' desired service configurations ";
$json = curl_ambari "$url_prefix/clusters/$cluster?fields=Clusters/desired_service_config_versions";
my %desired_service_config_versions = get_field_hash("Clusters.desired_service_config_versions");
my %incompat;
foreach my $service (sort keys %desired_service_config_versions){
    # not sure why this is a list, may cause overwrite if same service, multiple versions, current clusters don't have more than one item to test though
    # if this hits you please raise a ticket at https://github.com/harisekhon/nagios-plugins/issues
    my @list = get_field2_array(\%desired_service_config_versions, "$service");
    foreach my $settings (@list){
        my %settings = %{$settings};
        if(not defined($settings{"compatibleWithCurrentStack"})){
            quit "UNKNOWN", "field compatibleWithCurrentStack not found for service '$service'! $nagios_plugins_support_msg_api";
        }
        if(not defined($settings{"is_cluster_compatible"})){
            quit "UNKNOWN", "field is_cluster_compatible not found for service '$service'! $nagios_plugins_support_msg_api";
        }
        if(not defined($settings{"is_current"})){
            quit "UNKNOWN", "field is_current not found for service '$service'! $nagios_plugins_support_msg_api";
        }
        my $stack_compat    = $settings{"compatibleWithCurrentStack"};
        my $current         = $settings{"is_current"};
        my $cluster_compat  = $settings{"is_cluster_compatible"};
        if(not $stack_compat or not $cluster_compat){
            $incompat{$service}{"stack_compat"} = $stack_compat;
            $incompat{$service}{"cluster_compat"} = $cluster_compat;
            $incompat{$service}{"current"} = $current;
        }
    }
}
if(%incompat){
    critical;
    $msg .= "not compatible - ";
    foreach my $service (sort keys %incompat){
        $msg .= "$service: cluster compatible = " . strBool($incompat{$service}{"cluster_compat"})
                     . ", compatible with current stack = "   . strBool($incompat{$service}{"stack_compat"})
                     . ", is current = " . strBool($incompat{$service}{"current"}) . " - ";
    }
    $msg =~ s/ - $//;
} else {
    $msg .= "all compatible";
}

vlog2;
quit $status, $msg;
