#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 21:08:10 +0000 (Sun, 17 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

our $DESCRIPTION = "Nagios Plugin to check a Redis server's stats

1. Fetches one or more stats from specified Redis server. Defaults to fetching all stats
2. If specifying a single stat, checks the result matches expected value or warning/critical thresholds if specified
3. Outputs perfdata for all float value stats for graphing";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Redis;
use Redis;
use Time::HiRes 'time';

my $statlist;

my $expected;

%options = (
    %redis_options,
    "s|stats=s"        => [ \$statlist,     "Stats to retrieve, comma separated (default: all)" ],
    "e|expected=s"     => [ \$expected,     "Expected value for stat. Optional, only valid when a single stat is given" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
);

if($progname eq "check_redis_version.pl"){
    $DESCRIPTION = "Nagios Plugin to check a Redis server's version";
    $statlist = "redis_version";
    $options{"e|expected=s"} = [ \$expected,     "Expected Redis version" ];
    delete $options{"s|stats=s"};
    delete $options{"w|warning=s"};
    delete $options{"c|critical=s"};
}

@usage_order = qw/host port password stats expected warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my @stats;
if(defined($statlist)){
    unless($statlist eq "all"){
        @stats = split(",", $statlist);
        foreach my $stat (@stats){
            $stat =~ /^([\w_-]+)$/;
            $stat = $1;
            vlog_options "stat", $stat;
        }
        @stats or usage "no valid stats specified";
    }
}
@stats = uniq_array @stats if @stats;
if(scalar @stats > 1 and (defined($warning) or defined($critical) or defined($expected))){
    usage "cannot specify expected value or thresholds when specifying more than one statistic";
}
#$user       = validate_user($user);
#$password   = validate_password($password) if $password;
validate_int($precision, 1, 20, "precision");
unless($precision =~ /^(\d+)$/){
    code_error "precision is not a digit and has already passed validate_int()";
}
$precision = $1;
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

my $redis = connect_redis(host => $host, port => $port, password => $password) || quit "CRITICAL", "failed to connect to redis server '$hostport'";;

my $start_time = time;
my $info_hash;
try {
    $info_hash  = $redis->info
};
catch_quit "failed to retrieve stats from redis server '$hostport'";
my $time_taken = sprintf("%0.${precision}f", time - $start_time);
$info_hash or quit "UNKNOWN", "failed to retrieve stats (empty info hash returned) from redis server '$hostport'";
vlog2 "collected stats in $time_taken secs";

vlog2 "closing connection";
$redis->quit;

if($verbose > 2){
    print "\n";
    hr;
    print "#" . " " x 35 . "Stats\n";
    hr;
}
$msg = "";
my $msgperf = "";
my $stat_value;
if(@stats){
    foreach(@stats){
        unless(defined($$info_hash{$_})){
            quit "UNKNOWN", "no stat found: $_";
        }
        $msg .= "$_=$$info_hash{$_} ";
        vlog3 "$_=$$info_hash{$_}";
        if(isFloat($$info_hash{$_})){
            $msgperf .= "$_=$$info_hash{$_} ";
        }
    }
} else {
    foreach(sort keys %$info_hash){
        $msg .= "$_=$$info_hash{$_} ";
        vlog3 "$_=$$info_hash{$_}";
        if(isFloat($$info_hash{$_})){
            $msgperf .= "$_=$$info_hash{$_} ";
        }
    }
}
hr if $verbose > 2;

$msg =~ s/ $//;
$msgperf =~ s/ $//;
$msgperf .= msg_perf_thresholds(1) if(scalar @stats == 1 and isFloat($$info_hash{$stats[0]}));

if(scalar @stats == 1){
    if(defined($expected)){
        unless($$info_hash{$stats[0]} eq $expected){
            quit "CRITICAL", "$stats[0] returned '$$info_hash{$stats[0]}', expected '$expected'";
        }
    }
    if(defined($warning) or defined($critical)){
        if(isFloat($$info_hash{$stats[0]})){
            check_thresholds($$info_hash{$stats[0]});
        } else {
            quit "UNKNOWN", "non-float value returned for stat '$stats[0]', got '$$info_hash{$stats[0]}', cannot evaluate";
        }
    }
}

$msg .= ", queried server in $time_taken secs | ";
$msg .= "$msgperf " if $msgperf;
$msg .= "query_time=${time_taken}s";

vlog2;
quit $status, $msg;
