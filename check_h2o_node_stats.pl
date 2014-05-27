#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-05 22:03:20 +0100 (Sat, 05 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

my @stats = qw(
    free_disk_bytes
    free_mem_bytes
    max_disk_bytes
    max_mem_bytes
    num_cpus
    num_keys
    open_fds
    rpcs
    tcps_active
    tot_mem_bytes
    value_size_bytes
);

$DESCRIPTION = "Nagios Plugin to check stats for given node in an H20 machine learning cluster via REST API

Stats collected:

" . join("\n", @stats) . "
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

our $ua = LWP::UserAgent->new;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(54321);

env_creds("H2O");

my $stats;
my $list_nodes;

%options = (
    %hostoptions,
    "s|stats=s"         => [ \$stats,       "Stats to display, comma separated, see --help header for available stats. Thresholds are checked when specifying just one stat" ],
    "list-nodes"        => [ \$list_nodes,  "List nodes in H2O cluster and exit" ],
    %thresholdoptions,
);
@usage_order = qw/host port stats list-nodes warning critical/;

get_options();

$host        = validate_host($host);
$port        = validate_port($port);
my @stats2;
if($stats){
    foreach my $stat (split(/\s*[,\s]\s*/, $stats)){
        grep(/^$stat$/, @stats) or usage "invalid stat given, see --help header for list of valid stats";
        push(@stats2, $stat);
    }
    @stats2 = uniq_array @stats2;
    @stats or usage "no valid metrics specified";
}
@stats2 or @stats2 = @stats;
validate_thresholds() if scalar @stats2 == 1;

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

my %stats;
my $found_node = 0;
foreach my $node (@{$json->{"nodes"}}){
    defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
    if($node->{"name"} eq $json->{"node_name"}){
        $found_node = 1;
        foreach(@stats2){
            $stats{$_} = $node->{$_};
            $stats{$_} = 0 if $stats{$_} eq "N/A";
            isInt($stats{$_}) or quit "UNKNOWN", sprintf("field '$_' is not an integer! (returned: '%s')", $stats{$_});
        }
        last;
    }
}
$found_node or quit "UNKNOWN", "failed to find node stats. $nagios_plugins_support_msg_api";

if(scalar keys %stats == 1){
    my $stat = join("", keys %stats);
    my $value = $stats{$stat};
    $msg .= sprintf("%s=%d", $stat, $value);
    check_thresholds($value);
    $msg .= sprintf(" | %s=%d", $stat, $value);
    $msg .= "b" if $stat =~ /_bytes/;
    msg_perf_thresholds();
} else {
    foreach(sort keys %stats){
        $msg .= sprintf("%s=%d ", $_, $stats{$_});
    }
    $msg .= "| ";
    foreach(sort keys %stats){
        $msg .= sprintf("%s=%d%s ", $_, $stats{$_}, ($_ =~ /_bytes/ ? "b" : "") );
    }
}

vlog2;
quit $status, $msg;
