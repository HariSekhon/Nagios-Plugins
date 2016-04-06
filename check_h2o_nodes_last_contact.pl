#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-05 22:03:20 +0100 (Sat, 05 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check last contact time lag for nodes in an 0xdata H2O machine learning cluster via REST API

Checks the highest last contact lag for all nodes from the given --host node's perspective

Since current time is taken from the local machine this program is running on, you must make sure NTP is running across all cluster nodes and this one. Any timestamps in the future will result in a Warning state

Tested on 0xdata H2O 2.2.1.3, 2.4.3.4, 2.6.1.5

TODO: H2O 3.x API has changed, updates required
";

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

our $ua = LWP::UserAgent->new;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(10, 60);
set_port_default(54321);

env_creds("H2O");

my $list_nodes;
my $node_name;

%options = (
    %hostoptions,
    %thresholdoptions,
);
@usage_order = qw/host port warning critical/;

get_options();

$host        = validate_host($host);
$port        = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/Cloud.json";

my $content = curl $url;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by H2O at '$url_prefix'";
};
vlog3(Dumper($json));

foreach(qw/node_name nodes/){
    defined($json->{$_}) or usage "field '$_' not defined in output returned from H2O. $nagios_plugins_support_msg_api";
}

isArray($json->{"nodes"}) or quit "UNKNOWN" , "'nodes' field is not an array as expected. $nagios_plugins_support_msg_api";

if($list_nodes){
    print "H2O cluster nodes:\n\n";
    foreach my $node (@{$json->{"nodes"}}){
        defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
        print $node->{"name"} . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $lag;
my $last_contact;
my $future_lag = 0;
my $highest_lag = 0;
my @lagging_nodes;
my $found_node = 0;
my $now = time;
# This result is actually worse since it's more sensitive to NTP jitter between nodes, better to take a timestamp locally first it'll usually be higher
#foreach my $node (@{$json->{"nodes"}}){
#    defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
#    if($node->{"name"} eq $json->{"node_name"}){
#        $found_node = 1;
#        defined($node->{"last_contact"}) or quit "UNKNOWN", sprintf("'last_contact' field not defined for node '%s'. %s", $node->{"name"}, $nagios_plugins_support_msg_api);
#        isInt($node->{"last_contact"}) or quit "UNKNOWN", sprintf("last contact epoch time is not an integer for node '%s'! %s", $node->{"name"}, $nagios_plugins_support_msg_api);
#        $now = floor($node->{"last_contact"}/1000.0);
#    }
#}
#quit "UNKNOWN", "failed to find current node in output. $nagios_plugins_support_msg" unless $found_node;
vlog2 "comparing each node's last contact timestamp to local machine's current timestamp $now";
foreach my $node (@{$json->{"nodes"}}){
    defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
    defined($node->{"last_contact"}) or quit "UNKNOWN", sprintf("'last_contact' field not defined for node '%s'. %s", $node->{"name"}, $nagios_plugins_support_msg_api);
    isInt($node->{"last_contact"}) or quit "UNKNOWN", sprintf("last contact epoch time is not an integer for node '%s'! %s", $node->{"name"}, $nagios_plugins_support_msg_api);
    $last_contact = floor($node->{"last_contact"}/1000.0);
    $lag = $now - $last_contact;
    vlog2 sprintf("node '%s' last contact '%s' => lag '%s' secs", $node->{"name"}, $last_contact, $lag);
    if($lag < 0){
        warning;
        $future_lag++;
    }
    $lag > $highest_lag and $highest_lag = $lag;
    if(defined($thresholds{"warning"}{"upper"}) and $lag > $thresholds{"warning"}{"upper"}){
            push(@lagging_nodes, $node->{"name"});
    }
}

plural $future_lag;
$msg .= "$future_lag node$plural have last contact time in the future! Check NTP across nodes and machine this program is running on. " if $future_lag;
$msg .= sprintf("highest contact lag = %s secs", $highest_lag);
check_thresholds($highest_lag);
if($verbose and @lagging_nodes){
    $msg .= ", lagging nodes: " . join(", ", sort @lagging_nodes);
}
$msg .= sprintf(" | highest_lag=%ds", $highest_lag);
msg_perf_thresholds();

vlog2;
quit $status, $msg;
