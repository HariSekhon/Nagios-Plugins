#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_cluster_mgt.html?lang=en

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Services (Map/Reduce, HDFS/GPFS, BigSQL, HBase etc) via BigInsights Console REST API

Checks either a given service or all services managed by BigInsights Console.

- Checks service Running
- Checks service last check lag time in seconds. It is normal for checks to occur 20 or 60 secs apart by default in BigInsights Console so the warning and critical thresholds default to 60 and 120 seconds respectively. Tunable via --warning/--critical switches
- outputs graphing perfdata of the check lags

Thanks to Simon Woodcock @ IBM who first told me about the REST API for BigInsights Console which gave me the idea to start writing monitoring plugins for the usual things like service status

Tested on IBM BigInsights Console 2.1.2.0";

# On BigInsights QuickStart VM it's 20 secs but on my 20 node cluster it's 60 secs between checks

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use POSIX 'floor';

set_threshold_defaults(60, 120);

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $service;
my $list_services = 0;

%options = (
    %biginsights_options,
    "s|service=s"       =>  [ \$service,        "Check state of a given service (checks all services by default). Use --list-services to see valid service names" ],
    "list-services"     =>  [ \$list_services,  "List services" ],
    %thresholdoptions,
);
splice @usage_order, 4, 0, qw/service list-services/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
#$service    = validate_alnum($service, "service") if defined($service);
if(defined($service)){
    $service =~ /^(\w[\w\s\/-]*\w)$/ or usage "invalid service name, must be alphanumeric, may include forward slashes, dashes and spaces in the middle";
    $service = $1;
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1 });
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $now = time;

my $content = curl_biginsights "/ClusterStatus/cluster_summary.json", $user, $password;

my $service_name;
my %services;

sub parse_service($){
    my $service = shift;
    isInt(get_field2($service, "ts")) or quit "UNKNOWN", "'ts' field is not an integer as required. $nagios_plugins_support_msg_api";
    $service_name                               = get_field2($service, "id");
    $services{$service_name}{"label"}           = get_field2($service, "label");
    $services{$service_name}{"running"}         = get_field2($service, "running");
    $services{$service_name}{"check_lag"}       = floor($now - ( get_field2($service, "ts") / 1000.0) );
}

isArray(get_field("items")) or quit "UNKNOWN", "'item' field returned by BigInsights Console is not an array as expected. $nagios_plugins_support_msg_api";
foreach(@{$json->{"items"}}){
    # This prevents collecting service ids for --list-services
    #if($service){
    #    next unless $service eq get_field2($_, "id");
    #}
    parse_service($_);
}

if($list_services){
    print "Services:\n\n";
    foreach(sort keys %services){
        printf "%-13s =>    %s\n", $_, $services{$_}{"label"};
    }
    exit $ERRORS{"UNKNOWN"};
}

my $found_service = 0;
$msg .= "BigInsights service";
$msg .= "s" unless $service;
$msg .= ": ";
my $msg_perf = " | ";
foreach (sort keys %services){
    if($service){
        next unless $service =~ /^$_$/i or $service =~ /^$services{$_}{"label"}$/i;
        $found_service = 1;
    }
    unless($services{$_}{"running"}){
        critical;
    }
    $msg .= sprintf("%s=%s check lag=%d secs",
                    $services{$_}{"label"},
                    ( $services{$_}{"running"} ? "running" : "STOPPED"),
                    $services{$_}{"check_lag"},
                   );
    check_thresholds($services{$_}{"check_lag"});
    $msg .= ", ";
    $msg_perf .= sprintf("'%s service check lag'=%ds", $services{$_}{"label"}, $services{$_}{"check_lag"}) . msg_perf_thresholds(1) . " ";
}
$msg =~ s/,\s*$//;
$msg .= $msg_perf;
if($service){
    if(not $found_service){
        quit "UNKNOWN", "failed to find service '$service'. Did you specify the correct service name? Use --list-services to see valid service names from BigInsights Console. If you're sure you've specified the correct service name as shown by --list-services: $nagios_plugins_support_msg_api";
    }
}

quit $status, $msg;
