#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 03:06:42 +0100 (Sun, 21 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a specific Riak key via HTTP Rest API

Checks:

1. reads a specified Riak key
2. checks key's returned value against expected regex (optional)
3. checks key's returned value against warning/critical range thresholds (optional)
   raises warning/critical if the value is outside thresholds or not a floating point number
4. outputs the read timing to a given precision for reporting and graphing
5. optionally outputs the key's value for graphing purposes

Tested on Riak 1.4.0, 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.7.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use Time::HiRes 'time';

my $ip;
my $ua = LWP::UserAgent->new;
my $header = "Hari Sekhon $progname version $main::VERSION";
$ua->agent($header);

set_port_default(8098);

my $default_precision = 4;
my $precision = $default_precision;

my $bucket;
my $key;
my $expected;
my $graph = 0;
my $units;

env_creds("Riak");

%options = (
    %hostoptions,
    "k|key=s"          => [ \$key,          "Key to read from Riak" ],
    "b|bucket=s"       => [ \$bucket,       "Bucket to read the key from (must be alphanumeric, contact me for an update if you need non alphanumeric bucket names)" ],
    "e|expected=s"     => [ \$expected,     "Expected regex for the given Riak key's value. Optional" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive) for the key's value. Optional" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive) for the key's value. Optional" ],
    "g|graph"          => [ \$graph,        "Graph key's value. Optional, use only if a floating point number is normally returned for it's values, otherwise will print NaN (Not a Number). The reason this is not determined automatically is because keys that change between floats and non-floats will result in variable numbers of perfdata tokens which will break PNP4Nagios" ],
    "u|units=s"        => [ \$units,        "Units to use if graphing key's value. Optional" ],
    "precision=i"      => [ \$precision,    "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port key bucket expected warning critical graph units precision/;
get_options();

$host      = validate_host($host);
$port      = validate_port($port);
$key       = validate_nosql_key($key, "riak");
$bucket    = validate_alnum($bucket, "bucket");
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

$ip        = validate_resolvable($host);

my $node   = "riak node '$host:$port'";
my $url    = "http://$ip:$port/riak/$bucket/$key";
vlog_option "url",    $url;
my $bucket_key = "key '$key' bucket '$bucket'";

my $http_timeout = sprintf("%.2f", $timeout - 0.5);
$http_timeout = 1 if $http_timeout < 1;
vlog2 "\nsetting http timeout to $http_timeout secs\n";
$ua->timeout($http_timeout);
$ua->show_progress(1) if $debug;

$status = "OK";

my $req = HTTP::Request->new('GET', $url);
vlog2 "reading $bucket_key from $node";
my $start_time  = time;
my $response    = $ua->request($req);
my $read_time   = sprintf("%0.${precision}f", time - $start_time);
my $status_line = $response->status_line;
my $value       = $response->content;
chomp $value;
vlog2 "status:  $status_line";
vlog3 "body:    $value\n";
if($response->code eq 200 and $response->message eq "OK"){
    $msg = "key '$key' in bucket '$bucket' has value '$value'";
} elsif($response->code eq 300 or $response->code eq "Multiple Choices"){
    warning;
    $msg = "MULTIPLE key read choices returned in $read_time secs";
} else {
    quit "CRITICAL", "failed to read from $node after $read_time secs: $status_line";
}

my $read_msg = " Read key from $node in $read_time secs | ";
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
    vlog2 "\nchecking key value '$value' against expected regex '$expected'\n";
    unless($value =~ $expected){
        quit "CRITICAL", "key '$key' in bucket '$bucket' on $node did not match expected regex! Got value '$value', expected regex match '$expected'.$read_msg";
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
