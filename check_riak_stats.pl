#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 02:09:23 +0100 (Sun, 21 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check Riak's /stats metrics";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple qw/get $ua/;
use JSON::XS;

my $default_port = 8098;
$port = $default_port;

my $metrics;
my $all_metrics;
my $expected_string;

%options = (
    "H|host=s"            => [ \$host,              "Riak node to connect to" ],
    "P|port=s"            => [ \$port,              "Port to connect to (defaults to $default_port)" ],
    "m|metrics=s"         => [ \$metrics,           "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "a|all-metrics"       => [ \$all_metrics,       "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    # TODO: add regex match here later
    "s|expected-string=s" => [ \$expected_string,   "Expected string for metric if one metric is given. Takes priority over threshold range metrics" ],
    "w|warning=s"         => [ \$warning,           "Warning  threshold or ran:ge (inclusive). Only applied when a single metric is given and that metric is a float" ],
    "c|critical=s"        => [ \$critical,          "Critical threshold or ran:ge (inclusive). Only applied when a single metric is given and that metric is a float" ],
);

@usage_order = qw/host port metrics all-metrics warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my $url     = "http://$host:$port/stats";
my %stats;
my @stats;
if($all_metrics){
    defined($metrics) and usage "cannot specify --all-metrics and specific --metrics at the same time!";
} else {
    defined($metrics) or usage "no metrics specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^[A-Z]+[\w:]*[A-Z]+$/i or usage "invalid metrics '$metric' given, must be alphanumeric, may contain underscores and colons in middle";
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
validate_resolveable($host);
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
            quit "UNKNOWN", "<10 stats collected from /stats page, this must be an error, try running with -vvv to see what the deal is";
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

# TODO: could improve to make this recursive for embedded arrays / hashes but not needed right now
sub riakStatToString($){
    my $var = $_[0];
    if(isArray($var)){
        return "[" . join(",", @{$var}) . "]";
    } elsif(isHash($var)){
        my $str = "{";
        foreach(sort keys %{$var}){
            $str .= "$_=$var->$_,";
        }
        $str =~ s/,$/}/;
        return $str;
    # TODO: for some reason values such as 1.0.3 from basho_stats_version are not determined by ref used in isScalar so having to assume Scalar instead
    #} elsif(isScalar($var)) {
    #    return $var;
    #} else {
    #    quit "UNKNOWN", "could not determine if var '$var' is array, hash or scalar in riakStatToString()";
    #}
    } else {
        return $var;
    }
}


sub parse_stats(){
    isJson($content) or quit "CRITICAL", "invalid json returned by '$host:$port'";
    my $json = decode_json $content;
    if($debug){
        use Data::Dumper;
        print Dumper($json);
    }
    foreach my $stat (sort keys %{$json}){
        # This can be a float, a string, an array etc
        if($all_metrics){
            $stats{$stat} = riakStatToString($json->{$stat});
        } else {
            foreach my $metric (@stats){
                if($metric eq $stat){
                    $stats{$metric} = riakStatToString($json->{$stat});
                    last;
                }
            }
        }
    }
    check_stats_parsed();
}
# ============================================================================ #

vlog2 "parsing metrics from '$url'";
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
    my $metrics_found=0;
    foreach(sort keys %stats){
        isFloat($stats{$_}) or next;
        $metrics_found = 1;
    }
    $msg .= "| " if $metrics_found;
    foreach(sort keys %stats){
        isFloat($stats{$_}) or next;
        $msg .= "$_=$stats{$_} ";
    }
} elsif(!$all_metrics and scalar @stats == 1){
    if(defined($expected_string)){
        unless($stats{$stats[0]} eq $expected_string){
            $msg .= "does not match expected string '$expected_string' !!";
            quit "CRITICAL", $msg;
        }
    } elsif(isFloat($stats{$stats[0]})){ # or quit "UNKNOWN", "threshold validation given for non-float metric '$stats[0]'";
        $msg =~ s/ $//;
        check_thresholds($stats{$stats[0]});
        $msg .= " | $stats[0]=$stats{$stats[0]};" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "") . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "");
    }
} else {
    my $metrics_found=0;
    foreach(sort keys %stats){
        isFloat($stats{$_}) or next;
        $metrics_found = 1;
    }
    $msg .= "| " if $metrics_found;
    foreach(sort keys %stats){
        isFloat($stats{$_}) or next;
        $msg .= "$_=$stats{$_} ";
    }
}

quit $status, $msg;
