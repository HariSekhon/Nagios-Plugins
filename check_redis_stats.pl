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

$DESCRIPTION = "Nagios Plugin to check a Redis server's stats";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Redis;
use Time::HiRes 'time';

my $default_port = 6379;
$port            = $default_port;

my $statlist;

my $expected;

my $default_precision = 5;
my $precision = $default_precision;

%options = (
    "H|host=s"         => [ \$host,         "Redis Host to connect to" ],
    "P|port=s"         => [ \$port,         "Redis Port to connect to (default: $default_port)" ],
    "s|stats=s"        => [ \$statlist,     "Stats to retrieve, comma separated (default: all). If specifying one stat then optionally check result against --warning/--critical thresholds or --expected value" ],
    #"u|user=s"         => [ \$user,         "User to connect with" ],
    #"p|password=s"     => [ \$password,     "Password to connect with" ],
    "e|expected=s"     => [ \$expected,     "Expected value for stat. Optional, only valid when a single stat is given" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
    "precision=i"      => [ \$precision,    "Number of decimal places for timings (default: $default_precision)" ],
);

if($progname eq "check_redis_version.pl"){
    $statlist = "redis_version";
    delete $options{"s|stats=s"};
    delete $options{"w|warning=s"};
    delete $options{"c|critical=s"};
}

@usage_order = qw/host port stats user password expected warning critical precision/;
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

my $hostport = $host . ( $verbose ? ":$port" : "" );
$host  = validate_resolvable($host);
vlog2 "connecting to redis server '$host:$port'";
my $redis;
try {
    $redis = Redis->new(server => "$host:$port");
};
catch_quit "failed to connect to redis server $hostport";
vlog2 "API ping";
$redis->ping or quit "CRITICAL", "API ping failed, not connected to server?";

my $start_time = time;
my $info_hash  = $redis->info || quit "CRITICAL", "failed to retrieve stats from redis server '$hostport'";;
my $time_taken = sprintf("%0.${precision}f", time - $start_time);
vlog2 "collected stats in $time_taken secs";

vlog2 "closing connection";
$redis->quit;

if($verbose > 2){
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
