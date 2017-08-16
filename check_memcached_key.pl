#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-05-28 22:23:05 +0000 (Sat, 28 May 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

our $DESCRIPTION = "Nagios Plugin to check a specific Memcached key via API

Checks:

1. reads the specified Memcached key
2. checks key's returned value against expected regex (optional)
3. checks key's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
4. records the read timing to a given precision for reporting and graphing
5. outputs the read timing and optionally the key's value for graphing purposes

Tested on Memcached from around 2010/2011, plus 1.4.4, 1.4.25
";

$VERSION = "0.10";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
# Why am I using a socket connection instead of one of the libraries out there? Easy portability. Plus the text protocol isn't hard :)
use IO::Socket;
use Time::HiRes 'time';

set_port_default(11211);
set_timeout_range(1, 60);

my $default_precision = 5;
my $precision = $default_precision;

my $server_name = "memcached";
my $couchbase   = 0;
my $ip;
my $key;
my $expected;
my $graph = 0;
my $units;

if($progname =~ /couchbase/i){
    $couchbase = 1;
    $server_name = "couchbase";
    $DESCRIPTION =~ s/Memcached key via/Couchbase key via Memcached/;
    $DESCRIPTION =~ s/reads the specified Memcached key/reads the specified Couchbase key/;
    env_creds("COUCHBASE");
} else {
    env_creds("MEMCACHED");
}

%options = (
    %hostoptions,
    "k|key=s"       => [ \$key,         "Key to read from " . ucfirst $server_name ],
    "e|expected=s"  => [ \$expected,    "Expected regex for the given " . ucfirst $server_name . " key's value. Optional" ],
    "w|warning=s"   => [ \$warning,     "Warning  threshold ra:nge (inclusive) for the key's value. Optional" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold ra:nge (inclusive) for the key's value. Optional" ],
    "g|graph"       => [ \$graph,       "Graph key's value. Optional, use only if a floating point number is normally returned for it's values, otherwise will print NaN (Not a Number). The reason this is not determined automatically is because keys that change between floats and non-floats will result in variable numbers of perfdata tokens which will break PNP4Nagios" ],
    "u|units=s"     => [ \$units,       "Units to use if graphing key's value. Optional" ],
    "precision=i"   => [ \$precision,   "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port key expected warning critical graph units precision/;
get_options();

$host = validate_host($host);
$port = validate_port($port);
$key  = validate_nosql_key($key, "$server_name");
if(defined($expected)){
    $expected = validate_regex($expected);
}
vlog_option "graph", "true" if $graph;
if(defined($units)){
    $units = validate_units($units);
}
$precision = validate_int($precision, "precision", 1, 20);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 0, "integer" => 0 } );

vlog2;
set_timeout();

my $socket_timeout = sprintf("%.2f", $timeout / 2);
$socket_timeout = 1 if $socket_timeout < 1;
vlog2 "setting socket timeout to $socket_timeout secs as 1/2 of timeout to allow for connection + read operations within $timeout secs global timeout\n";

$status = "OK";

vlog2 "connecting to $host:$port";
my $start_time = time;
$ip = validate_resolvable($host);
my $conn = IO::Socket::INET->new (
                                    Proto    => "tcp",
                                    PeerAddr => $ip,
                                    PeerPort => $port,
                                    Timeout  => $socket_timeout,
                                 ) or quit "CRITICAL", "Failed to connect to '$host:$port': $!";
my $connect_time = sprintf("%0.${precision}f", time - $start_time);
vlog2 "OK connected in $connect_time secs\n";
$conn->autoflush(1) or quit "UNKNOWN", "failed to set autoflush on socket: $!";
vlog3 "set autoflush on";

my $memcached_read_cmd   = "get $key\r\n";

vlog3 "\nsending read request: $memcached_read_cmd";
my $read_start_time = time;
print $conn $memcached_read_cmd or quit "CRITICAL", "failed to read back key/value from $server_name on '$host:$port': $!";

my $value;
my $flags = '\d+';
my $bytes = '\d+';
my $value_regex = "^VALUE $key $flags $bytes";
my $value_seen = 0;
vlog3 "value regex:       $value_regex\n";
while(<$conn>){
    s/\r\n$//;
    vlog3 "$server_name response: $_";
    last if /END/;
    if($_ =~ /$value_regex/){
        $value_seen = 1;
        next;
    }
    quit "CRITICAL", "unexpected response returned instead of VALUE <key> <flags> <bytes>: $_" unless $value_seen;
    $value .= $_;
}
my $read_time= sprintf("%0.${precision}f", time - $read_start_time);
vlog2 "read request completed in $read_time secs\n";

unless(defined($value)){
    quit "CRITICAL", "key '$key' does not exist";
}

close $conn;
vlog2 "closed connection\n";

my $time_taken = time - $start_time;
$time_taken = sprintf("%.${precision}f", $time_taken);
vlog2 "total time taken for connect => read => close: $time_taken secs\n";

$msg = "key '$key' has value '$value'";
my $read_msg = " Read key in $read_time secs, total time $time_taken secs | ";

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
$read_msg .= "total_time=${time_taken}s read_time=${read_time}s";

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
