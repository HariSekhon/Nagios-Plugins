#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-11 12:59:27 +0000 (Mon, 11 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to parse metrics from a given Hadoop daemon's /metrics page

Currently supports metrics for sections:

JobTracker:     jvm
                mapred
                fairscheduler (specify -m 'pool:<name>:<map|reduce>:<metric_name>')

TaskTracker:    jvm
                mapred

HBase Master /
      RegionServer:     jvm
                        rpc
                        hbase  (requires -m <metric> prefix of one of the following to disambiguate metrics since some appear in more than one section)
                               - 'master:',
                               - 'regionserver:'
                               - 'RegionServerDynamicStatistics:'

UPDATE: newer /metrics pages are often blank. See check_hadoop_jmx.pl for jmx metrics & info instead

Tested on MRv1 JobTracker/TaskTracker, HBase 0.94
";

$VERSION = "0.4.1";

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

env_vars(["HOST"], \$host);

%options = (
    "H|host=s"         => [ \$host,         "Host to connect to (\$HOST)" ],
    "P|port=s"         => [ \$port,         "Port to connect to (eg. JobTracker 50030, TaskTracker 50060, HBase Master 60010, HBase RegionServer 60030)" ],
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "a|all-metrics"    => [ \$all_metrics,  "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port metrics all-metrics warning critical/;
get_options();

$host       = validate_host($host);
$host       = validate_resolvable($host);
$port       = validate_port($port);
my $url     = "http://$host:$port/metrics?format=json";
my %stats;
my @stats;
if($all_metrics){
    defined($metrics) and usage "cannot specify --all-metrics and specific --metrics at the same time!";
} else {
    defined($metrics) or usage "no metrics specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^[A-Za-z]+[\w:]*[A-Za-z]+$/i or usage "invalid metric '$metric' given, must be alphanumeric, may contain underscores and colons in middle";
        grep(/^$metric$/, @stats) or push(@stats, $metric);
    }
    @stats or usage "no valid metrics specified";
    @stats = uniq_array @stats;
}
validate_thresholds();

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

# ============================================================================ #
# lifted from my check_hadoop_jobtracker.pl plugin, modified to support $all_metrics
my $content = curl $url, "hadoop daemon $host:$port";

sub check_stats_parsed(){
    if($all_metrics){
        if(scalar keys %stats == 0){
            if($port == 50070 or $port == 50075){
                quit "UNKNOWN", "no stats collected from /metrics page, NameNode and DataNode /metrics pages did not export any metrics at the time of writing, see --help description for daemons supporting this information";
            } else {
                quit "UNKNOWN", "no stats collected from /metrics page (daemon recently started? Also, some newer versions of Hadoop do not populate this, see adjacent check_*_jmx.pl instead)";
            }
        }elsif(scalar keys %stats < 10){
            quit "UNKNOWN", "<10 stats collected from /metrics page (daemon recently started?). This could also be an error, try running with -vvv to see what the deal is";
        }
        foreach(sort keys %stats){
            vlog2 "stats $_ = $stats{$_}";
        }
    } else {
        foreach(@stats){
            unless(defined($stats{$_})){
                vlog2;
                quit "UNKNOWN", "failed to find $_ in output from '$host:$port'";
            }
            vlog2 "stats $_ = $stats{$_}";
        }
    }
    vlog2;
}

sub parse_stats(){
    #isJson($content) or quit "CRITICAL", "invalid json returned by '$host:$port'";
    my $json;
    try{
        $json = decode_json $content;
    };
    catch{
        quit "CRITICAL", "invalid json returned by '$host:$port'";
    };
    if($debug){
        use Data::Dumper;
        print Dumper($json);
        print "\n";
    }
    foreach my $section (qw/mapred jvm rpc hbase/){
        #defined($json->{$section}) or quit "UNKNOWN", "no $section section found in json output";
        defined($json->{$section}) or next;
        foreach my $subsection (sort keys %{$json->{$section}}){
            if(scalar(@{$json->{$section}->{$subsection}}) > 1){
                quit "UNKNOWN", "more than one $section $subsection section detected, code updates and user specification required to delve deeper";
            }
            defined($json->{$section}->{$subsection}[0][1]) or next;
            foreach my $stat (sort keys %{$json->{$section}->{$subsection}[0][1]}){
                defined($stats{$stat}) and quit "UNKNOWN", "detected more than one metric of the same name ($stat), code may need extension to handle extra context";
                my $context = "";
                if($section eq "hbase"){
                    $context = "$subsection:";
                }
                if($all_metrics){
                    defined($json->{$section}->{$subsection}[0][1]{$stat}) or quit "UNKNOWN", "\$json->{$section}->{$subsection}[0][1]{$stat} is not defined";
                    $stats{$context . $stat} = $json->{$section}->{$subsection}[0][1]{$stat};
                    isFloat($stats{$context . $stat}) or quit "UNKNOWN", "non-float metric returned '$stat' = " . $stats{$context . $stat} . " from $section $subsection";
                } else {
                    foreach my $metric (@stats){
                        if($metric eq $context . $stat){
                            $stats{$metric} = $json->{$section}->{$subsection}[0][1]{$stat};
                            last;
                        }
                    }
                }
            }
        }
    }
    if(defined($json->{"fairscheduler"})){
        foreach (@{$json->{"fairscheduler"}{"pools"}}){
            my $pool = "pool:" . $_->[0]{"name"} . ":" . lc $_->[0]{"taskType"};
            foreach my $stat (sort keys %{$_->[1]}){
                defined($stats{"pool:$stat"}) and quit "UNKNOWN", "detected more than one metric of the same name (pool:$stat), code may need extension to handle extra context";
                $stats{"$pool:$stat"} = $_->[1]{$stat};
            }
        }
    }
    check_stats_parsed();
}
# ============================================================================ #

vlog2 "parsing metrics from '$host:$port'\n";
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
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_} ";
    }
}

quit $status, $msg;
