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

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Agents via the BigInsights Console REST API

Tested on IBM BigInsights Console 2.1.2.0";

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

set_port_default(8080);
set_threshold_defaults(0, 1);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api = "data/controller";

our $protocol = "http";

my $agents;

%options = (
    %hostoptions,
    %useroptions,
    "agents"    =>  [ \$agents,     "Check agent states. Thresholds apply to stoppedAgent counts" ],
    %tlsoptions,
    %thresholdoptions,
);
@usage_order = qw/host port user password tls ssl-CA-path tls-noverify warning critical/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds();

tls_options();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

my $url = "$url_prefix/$api/ClusterStatus/cluster_summary.json";

my $content = curl $url, "IBM BigInsights Console", $user, $password;
my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix', did you try to connect to the SSL port without --tls?";
};
vlog3(Dumper($json));

$json->{"items"} or quit "UNKNOWN", "'items' field not found in json output. $nagios_plugins_support_msg_api";
my $monitoring;
isArray($json->{"items"}) or quit "UNKNOWN", "'items' field is not an array as expected. $nagios_plugins_support_msg_api";
foreach my $item (@{$json->{"items"}}){
    defined($item->{"id"}) or quit "UNKNOWN", "'id' field not found in json output. $nagios_plugins_support_msg_api";
    if($item->{"id"} eq "monitoring"){
        $monitoring = $item;
    }
}
defined($monitoring) or quit "UNKNOWN", "couldn't find monitoring item in json. $nagios_plugins_support_msg_api";
foreach(qw/runningAgents stoppedAgents/){
    $msg .= sprintf("%s = %s, ", $_, $monitoring->{$_});
}
$msg =~ s/, $//;
check_thresholds($monitoring->{"stoppedAgents"});
$msg .= sprintf(", operationalAgents = %s | runningAgents=%d stoppedAgents=%d", $monitoring->{"operationalAgents"}, $monitoring->{"runningAgents"}, $monitoring->{"stoppedAgents"});
msg_perf_thresholds();
$msg .= sprintf(" operationalAgents=%d", $monitoring->{"operationalAgents"});

quit $status, $msg;
