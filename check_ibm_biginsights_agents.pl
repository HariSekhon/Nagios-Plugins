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

Checks:

- stopped agents (includes dead) vs thresholds (default: w=0, c=1)
- operational agents vs running agents (warning if differ)

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.2";

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

my $skip_operational_check;

%options = (
    %hostoptions,
    %useroptions,
    "skip-operational-check"    =>  [ \$skip_operational_check, "Do not check operational agents vs running agents (only checks stopped agents vs thresholds)" ],
    %tlsoptions,
    %thresholdoptions,
);
@usage_order = qw/host port user password skip-operational-check tls ssl-CA-path tls-noverify warning critical/;

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
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix'. Try with -vvv to see full output";
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
foreach(qw/runningAgents stoppedAgents operationalAgents live dead/){
    defined($monitoring->{$_}) or quit "UNKNOWN", "'$_' field not found in monitoring output. $nagios_plugins_support_msg_api";
    isInt($monitoring->{$_})   or quit "UNKNOWN", "'$_' field was not an integer as expected (returned: " . $monitoring->{$_} . ")! $nagios_plugins_support_msg_api";
}
if($skip_operational_check){
    vlog2 "\nskipping operational vs running agents check" if $skip_operational_check;
} else {
    vlog2 "checking operational agents == running agents";
    my $non_operational_agents = $monitoring->{"runningAgents"} - $monitoring->{"operationalAgents"};
    if($non_operational_agents < 0){
        unknown;
        my $msg2 = "non-operational agents '$non_operational_agents' < 0 !!";
        vlog2 "\n** $msg2\n";
        $msg = "$msg2 $nagios_plugins_support_msg_api. $msg";
    } elsif($non_operational_agents != 0){
        warning;
        $msg = sprintf("%s non-operational agents detected. $msg", $non_operational_agents);
    }
}
foreach(qw/runningAgents stoppedAgents/){
    $msg .= sprintf("%s = %s, ", $_, $monitoring->{$_});
}
$msg =~ s/, $//;
vlog2 "checking stoppedAgents against thresholds";
check_thresholds($monitoring->{"stoppedAgents"});
$msg .= sprintf(", operationalAgents = %s, live = %s, dead = %s | runningAgents=%d stoppedAgents=%d", $monitoring->{"operationalAgents"}, $monitoring->{"live"}, $monitoring->{"dead"}, $monitoring->{"runningAgents"}, $monitoring->{"stoppedAgents"});
msg_perf_thresholds();
$msg .= sprintf(" operationalAgents=%d live=%d dead=%d", $monitoring->{"operationalAgents"}, $monitoring->{"live"}, $monitoring->{"dead"});

vlog2;
quit $status, $msg;
