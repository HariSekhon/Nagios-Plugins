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

$DESCRIPTION = "Nagios Plugin to check Riak's /stats metrics

Checks:

1. fetches one or more stats
2. checks stat's value against expected regex (optional)
3. checks stat's value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number";

$VERSION = "0.7";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';
use JSON::XS;

my $default_port = 8098;
$port = $default_port;

my $metrics;
my $all_metrics;
my $expected;

%options = (
    "H|host=s"            => [ \$host,              "Riak node to connect to" ],
    "P|port=s"            => [ \$port,              "Port to connect to (defaults to $default_port)" ],
    "m|metrics=s"         => [ \$metrics,           "Metric(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single metrics is given" ],
    "a|all-metrics"       => [ \$all_metrics,       "Grab all metrics. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "e|expected=s"        => [ \$expected,          "Expected regex for metric if one metric is given. Checked before range thresholds. Optional" ],
    "w|warning=s"         => [ \$warning,           "Warning  threshold or ran:ge (inclusive). Optional" ],
    "c|critical=s"        => [ \$critical,          "Critical threshold or ran:ge (inclusive). Optional" ],
);

@usage_order = qw/host port metrics all-metrics expected warning critical/;
get_options();

$host       = validate_host($host);
$host       = validate_resolvable($host);
$port       = validate_port($port);
my $url     = "http://$host:$port/stats";
my %stats;
my @stats;
if($all_metrics){
    defined($metrics) and usage "cannot specify --all-metrics and specific --metrics at the same time!";
} else {
    defined($metrics) or usage "no metrics specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^[A-Z]+[\w:]*[A-Z0-9]+$/i or usage "invalid metrics '$metric' given, must be alphanumeric, may contain underscores and colons in middle";
        grep(/^$metric$/, @stats) or push(@stats, $metric);
    }
    @stats or usage "no valid metrics specified";
}
if(defined($expected)){
    ($all_metrics or scalar @stats != 1) and usage "can only specify expected value when giving a single stat";
    $expected = validate_regex($expected);
}
if(($all_metrics or scalar @stats != 1) and ($warning or $critical)){
    usage "can only specify warning/critical thresholds when giving a single stat";
}
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 0, "integer" => 0 } );

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

# ============================================================================ #
# lifted from my check_hadoop_jobtracker.pl plugin, modified to support $all_metrics
my $content = curl $url,"Riak node $host";

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

my $value;
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
    $msg =~ s/ $//;
    $value = $stats{$stats[0]};
    if(defined($expected)){
        vlog2 "\nchecking stat value '$value' against expected regex '$expected'\n";
        unless($value =~ $expected){
            $msg .= " does not match expected regex '$expected'!!";
            quit "CRITICAL", $msg;
        }
    }
    my $isFloat = isFloat($value);
    my $non_float_err = ". Value is not a floating point number!";
    if($critical){
        unless($isFloat){
            critical;
            $msg .= $non_float_err;
        }
    } elsif($warning){
        unless($isFloat){
            warning;
            $msg .= $non_float_err;
        }
    }
    my ($threshold_ok, $threshold_msg);
    if($isFloat){
        ($threshold_ok, $threshold_msg) = check_thresholds($value, 1);
        if(!$threshold_ok){
            $msg .= " $threshold_msg";
        }
        $msg .= " | $stats[0]=$value" . msg_perf_thresholds(1);
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
