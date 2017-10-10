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

$DESCRIPTION = "Nagios Plugin to check the Ambari health report for a cluster via Ambari REST API

Checks for UNHEALTHY status in Ambari's health report and returns CRITICAL if found.

Returns WARNING for INIT and maintenance states, but this is ignorable in Nagios configuration if desired.

HEARTBEAT_LOST returns UNKNOWN. Ambari also has it's own UNKNOWN, which returns the same.

Tested on Ambari 2.1.0, 2.1.2, 2.2.1, 2.5.1 on Hortonworks HDP 2.2, 2.3, 2.4, 2.6";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

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

$msg = "Ambari health report: ";
my $msg2 = "";
$json = curl_ambari "$url_prefix/clusters/$cluster?fields=Clusters/health_report";
my %health_summary = get_field_hash("Clusters.health_report");
my @health_categories = qw(
    Host/host_status/ALERT
    Host/host_status/UNHEALTHY
    Host/host_state/UNHEALTHY
    Host/host_state/HEARTBEAT_LOST
    Host/host_status/UNKNOWN
    Host/host_state/INIT
    Host/host_state/HEALTHY
    Host/host_status/HEALTHY
    Host/maintenance_state
);
# exclude this we already have a stale config check
my @excluded_categories = qw(
    Host/stale_config
);
foreach my $health_category (sort keys %health_summary){
    if(not grep { $_ eq $health_category } @health_categories){
        next if grep { $_ eq $health_category } @excluded_categories;
        quit "UNKNOWN", "unknown health category '$health_category' found in response from Ambari server. $nagios_plugins_support_msg_api";
    }
}
foreach my $health_category (@health_categories){
    if(defined($health_summary{$health_category})){
        my $val = $health_summary{$health_category};
        $health_category =~ s/^Host\///;
        if(not isInt($val)){
            quit "UNKNOWN", "result '$val' for health category '$health_category' is not an integer as expected! $nagios_plugins_support_msg_api";
        }
        $msg .= "$health_category=$val, ";
        $msg2 .= "'$health_category'=$val ";
        if($health_category =~ /ALERT|UNHEALTHY/i and $val > 0){
            critical;
        } elsif($health_category =~ /INIT|MAINTENANCE/i and $val > 0){
            warning;
        } elsif($health_category =~ /UNKNOWN|HEARTBEAT_LOST/ and $val > 0){
            unknown;
        }
    } else {
        quit "UNKNOWN", "health category '$health_category' was not found in response from Ambari server. $nagios_plugins_support_msg_api";
    }
}
$msg =~ s/, $//;
$msg .= " | " . $msg2;

vlog2;
quit $status, $msg;
