#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Services (Map/Reduce, HDFS/GPFS, BigSQL, HBase etc) via BigInsights Console REST API

Checks either a given service or all services managed by BigInsights Console.

- Checks service Running
- Checks service last check lag time in seconds. It is normal for checks to occur 20 secs apart by default in BigInsights Console so the warning and critical thresholds default to 30 and 60 seconds respectively. Tunable via --warning/--critical switches
- outputs graphing perfdata of the check lags

Tested on IBM BigInsights Console 2.1.2";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON;
use LWP::UserAgent;
use POSIX 'floor';

set_port_default(8080);
set_threshold_defaults(30, 60);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api = "data/controller";

our $protocol = "http";

my $service;
my $list_services = 0;

%options = (
    %hostoptions,
    %useroptions,
    "S|service=s"       =>  [ \$service,        "Check state of a given service (checks all services by default). Use --list-services to see valid service names" ],
    "list-services"     =>  [ \$list_services,  "List services" ],
    %tlsoptions,
    %thresholdoptions,
);
@usage_order = qw/host port user password service list-services tls ssl-CA-path tls-noverify warning critical/;

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

tls_options();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

my $url = "$url_prefix/$api/ClusterStatus/cluster_summary.json";

my $now = time;

my $content = curl $url, "IBM BigInsights Console", $user, $password;
my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix', did you try to connect to the SSL port without --tls?";
};
vlog3(Dumper($json));

my $service_name;

my %services;

# XXX: check for dead optionally
sub parse_service($){
    my $service = shift;
    # contrary to doc there is no ss field any more
    foreach(qw/id label running ts/){
        defined($service->{$_})   or quit "UNKNOWN", "'$_' field not found. $nagios_plugins_support_msg_api";
    }
    isInt($service->{"ts"}) or quit "UNKNOWN", "'ts' field is not an integer as required. $nagios_plugins_support_msg_api";
    $service_name    = $service->{"id"};
    #$services{$service_name}{"service_state"}  = $service->{"ss"};
    $services{$service_name}{"label"}           = $service->{"label"};
    $services{$service_name}{"running"}         = $service->{"running"};
    $services{$service_name}{"check_lag"}       = floor($now - ($service->{"ts"}/1000.0));
}

defined($json->{"items"}) or quit "UNKNOWN", "'item' field not returned by BigInsights Console. $nagios_plugins_support_msg_api";
isArray($json->{"items"}) or quit "UNKNOWN", "'item' field returned by BigInsights Console is not an array as expected. $nagios_plugins_support_msg_api";
foreach(@{$json->{"items"}}){
    # This prevents collecting service ids for --list-services
    #defined($_->{"id"})   or quit "UNKNOWN", "'id' field not found. $nagios_plugins_support_msg_api";
    #if($service){
    #    next unless $service eq $_->{"id"};
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
