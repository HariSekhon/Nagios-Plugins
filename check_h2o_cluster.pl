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

$DESCRIPTION = "Nagios Plugin to check an 0xdata H2O machine learning cluster via REST API

Checks:

- cloud healthy state
- consensus among H2O instances

Optional Checks:

- cloud name
- number of H2O instances in cloud
- cloud locked (stabilized - accepts no new members)
- uptime - ensure cloud has stayed up a minimum amount of seconds
- H2O version

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
use POSIX 'ceil';

our $ua = LWP::UserAgent->new;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(54321);

env_creds("H2O");

my $cloud_name;
my $list_nodes;
my $instances = 0;
my $locked    = 0;
my $uptime    = 0;
my $h2o_version;

%options = (
    %hostoptions,
    "C|cloud-name=s"    => [ \$cloud_name,  "Check cloud name matches expected regex" ],
    "n|instances"       => [ \$instances,   "Check number of instances in cloud, use --warning/--critical thresholds to specify limits" ],
    "l|locked"          => [ \$locked,      "Ensure H2O Cloud is locked, otherwise raise warning" ],
    "uptime=s"          => [ \$uptime,      "Check uptime minimum number of secs" ],
    "h2o-version=s"     => [ \$h2o_version, "Check H2O version matches expected regex" ],
    "list-nodes"        => [ \$list_nodes,  "List nodes in H2O cluster and exit" ],
    %thresholdoptions,
);
@usage_order = qw/host port cloud-name instances locked uptime h2o-version list-nodes warning critical/;

get_options();

$host        = validate_host($host);
$port        = validate_port($port);
$cloud_name  = validate_regex($cloud_name)  if ($cloud_name);
$h2o_version = validate_regex($h2o_version) if ($h2o_version);
if($uptime){
    isFloat($uptime) or usage "uptime must be an integer/float in seconds";
}
validate_thresholds(1, 1, { "simple" => "lower", "positive" => 1 }) if $instances;

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

my %details;
foreach(qw/cloud_size
           cloud_name
           node_name
           nodes
           version
           cloud_uptime_millis
           consensus
           cloud_healthy
           locked/){
    defined($json->{$_}) or quit "UNKNOWN", "field '$_' not defined in output returned from H2O. $nagios_plugins_support_msg_api";
    $details{$_} = $json->{$_};
}

if($list_nodes){
    isArray($json->{"nodes"}) or quit "UNKNOWN", "'nodes' field is not an array. $nagios_plugins_support_msg_api";
    print "H2O cluster nodes:\n\n";
    foreach my $node (@{$json->{"nodes"}}){
        defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
        print $node->{"name"} . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

foreach(qw/cloud_size cloud_uptime_millis/){
    isInt($details{$_}) or quit "UNKNOWN", sprintf("field '$_' is not an integer! (returned: '%s')", $details{$_});
}
my $uptime_secs = ceil($details{"cloud_uptime_millis"} / 1000.0);

if(defined($cloud_name)){
    unless($details{"cloud_name"} =~ /$cloud_name/i){
        critical;
        $msg .= "unexpected name for ";
    }
}

if($locked){
    $details{"locked"} or warning;
}

critical unless $details{"cloud_healthy"};
critical unless $details{"consensus"};

$msg .= sprintf("H2O cloud: '%s', instances: %d", $details{"cloud_name"}, $details{"cloud_size"});
check_thresholds($details{"cloud_size"});

$msg .= sprintf(", locked: %s, healthy: %s, consensus: %s, uptime: %d secs",
                ($details{"locked"} ? "yes" : "NO"),
                ($details{"cloud_healthy"} ? "yes" : "NO"),
                ($details{"consensus"} ? "yes" : "NO"),
                $uptime_secs,
              );
if($uptime_secs < $uptime){
    critical;
    $msg .= " ($uptime_secs < $uptime)";
}
$msg .= sprintf(", version '%s'", $details{"version"});
if(defined($h2o_version)){
    unless($details{"version"} =~ /$h2o_version/i){
        critical;
        $msg .= " (expected: '$h2o_version')";
    }
}
$msg .= sprintf(" | instances=%d", $details{"cloud_size"});
msg_perf_thresholds(undef, 1);

vlog2;
quit $status, $msg;
