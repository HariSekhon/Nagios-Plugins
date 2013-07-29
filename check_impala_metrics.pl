#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-29 19:19:45 +0100 (Mon, 29 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to fetch metrics from a given Impalad/StateStore debug UI";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

my $default_port = 25000;
$port = $default_port;

my $metrics = "";

%options = (
    "H|host=s"         => [ \$host,         "Impalad or StateStore to connect to" ],
    "P|port=s"         => [ \$port,         "Impalad or StateStore debug UI port (defaults to $default_port for Impalad, specify 25010 for StateStore)" ],
    "m|metrics=s"      => [ \$metrics,      "Metrics to fetch, comma separated. If one metric is given then warning and critical thresholds may optionally be applied to that metric. By default all metrics are fetched" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port metrics warning critical/;
get_options();

my $metric_regex = '[A-Za-z][\w\.-]+';

$host       = validate_hostname($host);
$port       = validate_port($port);
my @metrics;
if($metrics){
    @metrics = split(/\s*,\s*/, $metrics);
    foreach(@metrics){
        /$metric_regex/ or usage "invalid metric '$_' given";
    }
    @metrics = uniq_array @metrics;
}
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

# Impala 1.0 / 1.0.1 doesn't currently support &raw on this URI handler
my $url = "http://$host:$port/metrics";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->show_progress(1) if $debug;

vlog2 "querying Impalad debug UI metrics";
my $res = $ua->get($url);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = $res->content;
vlog3 "\ncontent:\n\n$content\n";
vlog2;

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

my %stats;
foreach(split("\n", $content)){
    if(/($metric_regex)\s*:\s*(\d+)\s*$/io){
        $stats{$1} = $2;
    } elsif(/($metric_regex):\s+(?:\w+:\s+\d+,\s+)*last\s*:\s*(\d+)\s*/io){
        # to catch last heartbeat stats
        $stats{$1} = $2;
    }
}

my @metrics_not_found;
if(@metrics){
    if(scalar @metrics eq 1){
        defined($metrics[0]) or quit "CRITICAL", "metric '$metrics[0] not found";
        $msg = "$metrics[0]=$stats{$metrics[0]}";
        check_thresholds($stats{$metrics[0]});
        $msg .= " | $metrics[0]=$stats{$metrics[0]}";
        quit $status, $msg;
    } else {
        foreach(@metrics){
            unless(defined($stats{$_})){
                push(@metrics_not_found, $_);
                next;
            }
            $msg .= "$_=$stats{$_} ";
        }
    }
} else {
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_} ";
    }
}

$msg .= "| $msg";
$msg =~ s/ $//;

if(@metrics_not_found){
    critical;
    $msg = "metrics not found: " . join(",", @metrics_not_found) . " -- $msg";
}

quit $status, $msg;
