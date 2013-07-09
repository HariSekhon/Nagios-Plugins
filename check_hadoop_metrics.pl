#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-11 12:59:27 +0000 (Mon, 11 Feb 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to parse metrics from a given Hadoop daemon's /metrics page";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use LWP::Simple qw/get $ua/;
use HariSekhonUtils;

my $metrics;

%options = (
    "H|host=s"         => [ \$host,         "Host to connect to" ],
    "P|port=s"         => [ \$port,         "Port to connect to" ],
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port metrics warning critical/;
get_options();

$host       = validate_hostname($host);
$port       = validate_port($port);
my $url     = "http://$host:$port/metrics";
defined($metrics) or usage "no metrics specified";
my @stats;
my %stats;
foreach(split(/\s*[,\s]\s*/, $metrics)){
    /^\w+$/ or usage "invalid metrics $_ given, must be alphanumeric with underscores";
    push(@stats, $_);
}
@stats or usage "no valid metrics specified";
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

# ============================================================================ #
# lifted from my check_hadoop_jobtracker.pl plugin
vlog2 "querying $url";
my $content = get $url;
my ($result, $err) = ($?, $!);
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "result: $result";
vlog2 "error:  " . ( $err ? $err : "<none>" ) . "\n";
if($result ne 0 or $err){
    quit "CRITICAL", "failed to connect to '$host:$port': $err";
}
unless($content){
    quit "CRITICAL", "blank content returned from '$host:$port'";
}

sub check_stats_parsed(){
    foreach(@stats){
        unless(defined($stats{$_})){
            vlog2;
            quit "UNKNOWN", "failed to find $_ in JobTracker output";
        }
        vlog2 "stats $_ = $stats{$_}";
    }
    vlog2;
}

sub parse_stats(){
    foreach my $line (split("\n", $content)){
        foreach my $stat (@stats){
            if($line =~ /^\s*$stat\s*=\s*(\d+(?:\.\d+)?)\s*$/){
                $stats{$stat} = $1;
                last;
            }
        }
    }
    check_stats_parsed();
}
# ============================================================================ #

vlog2 "parsing metrics from '$host:$port'";
parse_stats();

$msg = "";
foreach(@stats){
    $msg .= "$_=$stats{$_} ";
}
if(scalar @stats == 1){
    check_thresholds($stats{$stats[0]});
    $msg .= " | $stats[0]=$stats{$stats[0]};" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "") . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "");
} else {
    $msg .= "| ";
    foreach(@stats){
        $msg .= "$_=$stats{$_} ";
    }
}

quit "$status", "$msg";
