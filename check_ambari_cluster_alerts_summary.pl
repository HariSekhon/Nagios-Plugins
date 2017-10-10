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

$DESCRIPTION = "Nagios Plugin to check for Ambari alerts via Ambari REST API

Checks whether there are CRITICAL / WARNING / UNKNOWN alerts in Ambari and returns the corresponding status output and exit code.

MAINTENANCE and OK counts are also output along with perfdata for tracking how this changes over time.

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

$msg = "Ambari alerts: ";
my $msg2 = "";
$json = curl_ambari "$url_prefix/clusters/$cluster?fields=alerts_summary";
my %alerts_summary = get_field_hash("alerts_summary");
my @alert_categories = qw/CRITICAL WARNING UNKNOWN OK MAINTENANCE/;
foreach my $alert_category (sort keys %alerts_summary){
    if(not grep { $_ eq $alert_category } @alert_categories){
        quit "UNKNOWN", "unknown alert category '$alert_category' found in response from Ambari server. $nagios_plugins_support_msg_api";
    }
}
foreach my $alert_category (@alert_categories){
    if(defined($alerts_summary{$alert_category})){
        my $val = $alerts_summary{$alert_category};
        if(not isInt($val)){
            quit "UNKNOWN", "result '$val' for alert category '$alert_category' is not an integer as expected! $nagios_plugins_support_msg_api";
        }
        $msg .= "$alert_category=$val, ";
        $msg2 .= "'$alert_category'=$val ";
        if($alert_category eq "CRITICAL" and $val > 0){
            critical;
        } elsif($alert_category eq "WARNING" and $val > 0){
            warning;
        } elsif($alert_category eq "UNKNOWN" and $val > 0){
            unknown;
        }
    } else {
        quit "UNKNOWN", "alert category '$alert_category' was not found in response from Ambari server. $nagios_plugins_support_msg_api";
    }
}
$msg =~ s/, $//;
$msg .= " | " . $msg2;

vlog2;
quit $status, $msg;
