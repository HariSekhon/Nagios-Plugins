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

$DESCRIPTION = "Nagios Plugin to parse metrics from a given Hadoop daemon's /metrics page

Currently only supporting the jvm/mapred sections, Fair Scheduler stats from JobTracker may be supported in a later version";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple qw/get $ua/;
use JSON::XS;

my $metrics;
my $all_metrics;

%options = (
    "H|host=s"         => [ \$host,         "Host to connect to" ],
    "P|port=s"         => [ \$port,         "Port to connect to (eg. 50030 for JobTracker or 50060 for TaskTracker)" ],
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "a|all-metrics"    => [ \$all_metrics,  "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port metrics all-metrics warning critical/;
get_options();

$host       = validate_hostname($host);
$port       = validate_port($port);
my $url     = "http://$host:$port/metrics?format=json";
my %stats;
my @stats;
unless($all_metrics){
    defined($metrics) or usage "no metrics specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^\w+$/ or usage "invalid metrics '$metric' given, must be alphanumeric with underscores";
        grep(/^$metric$/, @stats) or push(@stats, $metric);
    }
    @stats or usage "no valid metrics specified";
}
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

# ============================================================================ #
# lifted from my check_hadoop_jobtracker.pl plugin, modified to support $all_metrics
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
    if($all_metrics){
        if(scalar keys %stats < 10){
            quit "UNKNOWN", "<10 stats collected from /metrics page, this must be an error, try running with -vvv to see what the deal is";
        }
        foreach(sort keys %stats){
            vlog2 "stats $_ = $stats{$_}";
        }
    } else {
        foreach(@stats){
            unless(defined($stats{$_})){
                vlog2;
                quit "UNKNOWN", "failed to find $_ in JobTracker output";
            }
            vlog2 "stats $_ = $stats{$_}";
        }
    }
    vlog2;
}

sub parse_stats(){
    isJson($content) or quit "CRITICAL", "invalid json returned by '$host:$port'";
    my $json = decode_json $content;
    if($debug){
        use Data::Dumper;
        print Dumper($json);
    }
    # TODO: support Fair Scheduler metrics for MAP and REDUCE sections later, right now only doing JVM and Mapred stats
    foreach my $section (qw/mapred jvm/){
        defined($json->{$section}) or quit "UNKNOWN", "no $section section found in json output";
        foreach my $subsection (sort keys %{$json->{$section}}){
            if(scalar(@{$json->{$section}->{$subsection}}) > 1){
                quit "UNKNOWN", "more than one $section $subsection section detected, code updates and user specification required to delve deeper";
            }
            foreach my $stat (sort keys %{$json->{$section}->{$subsection}[0][1]}){
                if($all_metrics){
                    $stats{$stat} = $json->{$section}->{$subsection}[0][1]{$stat};
                    isFloat($stats{$stat}) or quit "UNKNOWN", "non-float metric returned '$stat' = $stats{$stat} from $section $subsection";
                } else {
                    foreach my $metric (@stats){
                        if($metric eq $stat){
                            $stats{$metric} = $json->{$section}->{$subsection}[0][1]{$stat};
                            last;
                        }
                    }
                }
            }
        }
    }
    check_stats_parsed();
}
# ============================================================================ #

vlog2 "parsing metrics from '$host:$port'";
parse_stats();

$msg = "";
if($all_metrics){
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_} ";
    }
} else {
    foreach(@stats){
        $msg .= "$_=$stats{$_} ";
    }
}
if($all_metrics){
    $msg .= "| ";
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_} ";
    }
} elsif(!$all_metrics and scalar @stats == 1){
    $msg =~ s/ $//;
    check_thresholds($stats{$stats[0]});
    $msg .= " | $stats[0]=$stats{$stats[0]};" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "") . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "");
} else {
    $msg .= "| ";
    foreach(@stats){
        $msg .= "$_=$stats{$_} ";
    }
}

quit "$status", "$msg";
