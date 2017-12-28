#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 00:22:17 +0000 (Sun, 17 Nov 2013)
#  Continuation an idea from Q3/Q4 2012, inspired by other similar NoSQL plugins developed a few years earlier
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a specific Redis key via API

Checks:

1. reads a specified Redis key
2. checks key's returned value against expected regex (optional)
3. checks key's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
4. checks list length against warning/critical thresholds
5. records the read timing to a given precision for reporting and graphing
6. outputs the read timing and optionally the key's value for graphing purposes

Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

$VERSION = "0.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Redis;
use Redis;
use Time::HiRes qw/time sleep/;

my $key;
my $lkey;
my $expected;
my $graph = 0;
my $units;

%options = (
    %redis_options,
    %redis_options_database,
    "k|key=s"          => [ \$key,          "Key to read from Redis" ],
    "e|expected=s"     => [ \$expected,     "Expected regex for the given Redis key's value. Optional" ],
    "l|list"           => [ \$lkey,         "Key is a list, check its length from Redis" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive) for the key's value. Optional" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive) for the key's value. Optional" ],
    "g|graph"          => [ \$graph,        "Graph key's value. Optional, use only if a floating point number is normally returned for it's values, otherwise will print NaN (Not a Number). The reason this is not determined automatically is because keys that change between floats and non-floats will result in variable numbers of perfdata tokens which will break PNP4Nagios" ],
    "u|units=s"        => [ \$units,        "Units to use if graphing key's value. Optional" ],
);

@usage_order = qw/host port key lkey database password expected warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$key        = validate_nosql_key($key, "redis");
$password   = validate_password($password) if defined($password);
if(defined($database)){
    $database = validate_int($database, "database", 0, 15);
}
if(defined($expected)){
    $expected = validate_regex($expected);
}
vlog_option "graph", "true" if $graph;
if(defined($units)){
    $units = validate_units($units);
}
$precision = validate_int($precision, "precision", 1, 20);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );

vlog2;
set_timeout();

$status = "OK";

# all the checks are done in connect_redis, will error out on failure
my ($redis, $hostport) = connect_redis(host => $host, port => $port, password => $password);
if(defined($database)){
    vlog2 "selecting database $database on $hostport\n";
    try {
        $redis->select($database);
    };
    catch_quit "failed to change to database $database on $hostport";
}

vlog2 "reading key back from $hostport";
my $value;
my $start_time = time;
try {
    if ($lkey) {
        $value  = $redis->llen($key);
    } else {
        $value  = $redis->get($key);
    }
};
catch_quit "failed to get key '$key' from redis host $hostport";
my $read_time  = time - $start_time;
$read_time     = sprintf("%0.${precision}f", $read_time);

vlog2 "closing connection\n";
try {
    $redis->quit;
};

unless(defined($value)){
    quit "CRITICAL", "key '$key' not found in " . (defined($database) ? "database $database" : "default database 0");
}

$msg = "key '$key' has value '$value'";
my $read_msg = " Read key in $read_time secs | ";

if($graph){
    if(isFloat($value)){
        $read_msg .= "'$key'=$value";
        if(defined($units)){
            $read_msg .= "$units";
        }
        $read_msg .= msg_perf_thresholds(1);
    } else {
        $read_msg .= "'$key'=NaN";
    }
    $read_msg .= " ";
}
$read_msg .= "read_time=${read_time}s";

if(defined($expected)){
    vlog2 "checking key value '$value' against expected regex '$expected'\n";
    unless($value =~ $expected){
        quit "CRITICAL", "key '$key' did not match expected regex! Got value '$value', expected regex match '$expected'.$read_msg";
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
    if((!$threshold_ok or $verbose) and $threshold_msg){
        $msg .= " $threshold_msg.";
    }
}
$msg =~ s/ $//;
$msg .= "." unless $msg =~ /[\.\!]$/;

$msg .= $read_msg;

quit $status, $msg;
