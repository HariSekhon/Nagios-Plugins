#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 02:09:23 +0100 (Sun, 21 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Riak's stats and other settings exposed via the Basho Stats API such as Riak component versions

This is even how check_riak_version.pl is implemented through this plugin for Riak core, and you can explicitly query other components via this plugin, use --all -vv to get a convenient listing one per line of all the available stats.

Checks:

1. fetches one or more stats
2. checks stat's value against expected regex (optional)
3. checks stat's value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number

Tested on Riak 1.4.0, 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.8.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';
use JSON::XS;

set_port_default(8098);

env_creds("Riak");

my $metrics;
my $all_stats;
my $expected;

%options = (
    %hostoptions,
    "s|stat=s"            => [ \$metrics,           "Stat(s) to collect, comma separated. Output in the order specified for convenience. Optional thresholds will only be applied when a single stat is specified" ],
    "a|all"               => [ \$all_stats,         "Grab all stats. Useful if you don't know what to monitor yet or just want to graph everything" ],
    "e|expected=s"        => [ \$expected,          "Expected regex for stat if one stat is specified. Checked before range thresholds. Optional" ],
    "w|warning=s"         => [ \$warning,           "Warning  threshold or ran:ge (inclusive). Optional" ],
    "c|critical=s"        => [ \$critical,          "Critical threshold or ran:ge (inclusive). Optional" ],
);
@usage_order = qw/host port stat all expected warning critical/;

if($progname =~ /version/){
    delete $options{"s|stat=s"};
    delete $options{"a|all"};
    delete $options{"w|warning=s"};
    delete $options{"c|critical=s"};
    $metrics = "riak_core_version";
}
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my %stats;
my @stats;
if($all_stats){
    defined($metrics) and usage "cannot specify --all and specific --stats at the same time!";
} else {
    defined($metrics) or usage "no stat(s) specified";
    foreach my $metric (split(/\s*[,\s]\s*/, $metrics)){
        $metric =~ /^[A-Z]+[\w\.:]*[A-Z0-9]+$/i or usage "invalid stats '$metric' given, must be alphanumeric, may contain underscores, dots and colons in middle";
        grep(/^$metric$/, @stats) or push(@stats, $metric);
        vlog_option "stat", $metric;
    }
    @stats or usage "no valid stats specified";
}
if(defined($expected)){
    ($all_stats or scalar @stats != 1) and usage "can only specify expected value when giving a single stat";
    $expected = validate_regex($expected);
}
if(($all_stats or scalar @stats != 1) and ($warning or $critical)){
    usage "can only specify warning/critical thresholds when giving a single stat";
}
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 0, "integer" => 0 } );

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

$host = validate_resolvable($host);
my $url = "http://$host:$port/stats";

# ============================================================================ #
my $content = curl $url, "Riak node $host";

sub check_stats_parsed(){
    if($all_stats){
        vlog2 "checking all stats found at least 10 stats";
        if(scalar keys %stats < 10){
            quit "UNKNOWN", "<10 stats collected from /stats page, this must be an error, try running with -vvv to see what the deal is";
        }
        #foreach(sort keys %stats){
        #    vlog2 "stats $_ = '$stats{$_}'";
        #}
    } else {
        foreach my $requested_stat (@stats){
            vlog2 "checking $requested_stat was found";
            unless(defined($stats{$requested_stat})){
                vlog2;
                my $err = "failed to find $requested_stat in output from '$host:$port'";
                if(grep { $_ =~ /^\Q$requested_stat\E\./ } keys %stats){
                    $err .= ", but subkey(s) for $requested_stat were found, try -vv to see what was collected to specify a subnode if it's an array or hash";
                }
                quit "UNKNOWN", $err;
            }
            #vlog2 "stat found $requested_stat = '$stats{$requested_stat}'";
        }
    }
    vlog2;
}

# To check prototype before calling recursively
sub processStat($$);
sub processStat($$){
    my $name = shift;
    my $var  = shift;
    vlog3 "processing $name";
    if(isArray($var)){
        if(scalar @{$var} > 0){
            foreach(my $i=0; $i < scalar @{$var}; $i++){
                processStat("$name.$i", $$var[$i]);
            }
        } else {
            processStat("$name.0", "");
        }
    } elsif(isHash($var)){
        foreach my $key (keys %{$var}){
            processStat("$name.$key", $$var{$key});
        }
    } else {
        vlog2 "collected stat  $name='$var'";
        $stats{$name} = $var;
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
        print Dumper($json);
    }
    foreach my $stat (sort keys %{$json}){
        # This can be a float, a string, an array etc
        if($all_stats){
            processStat($stat, $json->{$stat});
        } else {
            foreach my $metric (@stats){
                my $metric2 = $metric;
                $metric2 =~ s/\..*$//;
                if($metric2 eq $stat){
                    processStat($stat, $json->{$stat});
                    last;
                }
            }
        }
    }
    check_stats_parsed();
}
# ============================================================================ #

vlog2 "parsing stats from '$url'";
parse_stats();

$msg = "";
if($all_stats){
    foreach(sort keys %stats){
        $msg .= "$_=$stats{$_} ";
    }
} else {
    foreach(@stats){
        $msg .= "$_=$stats{$_} ";
    }
}

my $value;
if($all_stats){
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
} elsif(!$all_stats and scalar @stats == 1){
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
        #($threshold_ok, $threshold_msg) = check_thresholds($value, 1);
        #if(!$threshold_ok){
        #    $msg .= " $threshold_msg";
        #}
        check_thresholds($value);
        $msg .= " | $stats[0]=$value";
        msg_perf_thresholds();
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
