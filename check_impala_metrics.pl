#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-29 19:19:45 +0100 (Mon, 29 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to fetch metrics from a given Impalad/StateStore debug UI";

$VERSION = "0.3.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';
use JSON::XS;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $default_port = 25000;
$port = $default_port;

my $metrics;
my $all_metrics = 0;

%options = (
    "H|host=s"         => [ \$host,         "Impalad or StateStore to connect to" ],
    "P|port=s"         => [ \$port,         "Impalad or StateStore debug UI port (defaults to $default_port for Impalad, specify 25010 for StateStore)" ],
    "m|metrics=s"      => [ \$metrics,      "Metrics to fetch, comma separated. If one metric is given then warning and critical thresholds may optionally be applied to that metric" ],
    "a|all-metrics"    => [ \$all_metrics,  "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port metrics all-metrics warning critical/;
get_options();

my $metric_regex = '[A-Za-z][\w\.-]+';

$host       = validate_host($host);
$host       = validate_resolvable($host);
$port       = validate_port($port);
my %stats;
my @stats;
if($all_metrics){
    defined($metrics) and usage "cannot specify --all-metrics and specific --metrics at the same time!";
} else {
    defined($metrics) or usage "no metrics specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^$metric_regex$/io or usage "invalid metric '$metric' given, must be alphanumeric, may contain dashes, dots and underscores";
        grep(/^$metric$/, @stats) or push(@stats, $metric);
    }
    @stats or usage "no valid metrics specified";
    @stats = uniq_array @stats;
}
validate_thresholds();

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

# Impala 1.0 / 1.0.1 doesn't currently support &raw on this URI handler
#my $url = "http://$host:$port/metrics";
# switched to /jsonmetrics
# Impala 1.0 / 1.0.1 doesn't currently support &raw on this URI handler
# Impala since CDH 5.4 switched to jsonmetrics?json
my $url = "http://$host:$port/jsonmetrics?json";

my $content = curl $url, "Impala debug UI metrics";

sub check_stats_parsed(){
    if($all_metrics){
        if(scalar keys %stats == 0){
            quit "UNKNOWN", "no stats collected from /metrics page (daemon recently started?)";
        }elsif(scalar keys %stats < 5){
            quit "UNKNOWN", "<5 stats collected from /metrics page (daemon recently started?). This could also be an error, try running with -vvv to see what the deal is";
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
    if($all_metrics){
        foreach my $metric (keys %{$json}){
            if(isFloat($json->{$metric})){
                $stats{$metric} = $json->{$metric};
            }
        }
    } else {
        foreach my $metric (@stats){
            defined($json->{$metric}) or quit "UNKNOWN", "metric '$metric' not found in output from Impala";
            if(isHash($json->{$metric})){
                defined($json->{$metric}{"last"}) or quit "UNKNOWN", "unrecognized metric/format detected for '$metric', ask author Hari Sekhon for an update";
                if(isFloat($json->{$metric}{"last"})){
                    $stats{$metric} = $json->{$metric}{"last"};
                }
            } else {
                if(isFloat($json->{$metric})){
                    $stats{$metric} = $json->{$metric};
                } else {
                    quit "UNKNOWN", "given metric '$metric' is not a float, cannot be used";
                }
            }
        }
    }
    check_stats_parsed();
}

# ============================================================================ #

vlog2 "parsing metrics from '$host:$port'\n";
parse_stats();

# ============================================================================ #

#foreach(split("\n", $content)){
#    if(/($metric_regex)\s*:\s*(\d+)\s*$/io){
#        $stats{$1} = $2;
#    } elsif(/($metric_regex):\s+(?:\w+:\s+\d+,\s+)*last\s*:\s*(\d+)\s*/io){
#        # to catch last heartbeat stats
#        $stats{$1} = $2;
#    }
#}
#unless(%stats){
#    quit "UNKNOWN", "no metrics found!";
#}
#
#my @metrics_not_found;
#if(@metrics){
#    if(scalar @metrics eq 1){
#        defined($metrics[0]) or quit "CRITICAL", "metric '$metrics[0] not found";
#        $msg = "$metrics[0]=$stats{$metrics[0]}";
#        check_thresholds($stats{$metrics[0]});
#        $msg .= " | $metrics[0]=$stats{$metrics[0]}";
#        quit $status, $msg;
#    } else {
#        foreach(@metrics){
#            unless(defined($stats{$_})){
#                push(@metrics_not_found, $_);
#                next;
#            }
#            $msg .= "$_=$stats{$_} ";
#        }
#    }
#} else {
#    foreach(sort keys %stats){
#        $msg .= "$_=$stats{$_} ";
#    }
#}
#
#$msg .= "| $msg";
#$msg =~ s/ $//;
#
#if(@metrics_not_found){
#    critical;
#    $msg = "metrics not found: " . join(",", @metrics_not_found) . " -- $msg";
#}

# ============================================================================ #

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
