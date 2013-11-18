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

$DESCRIPTION = "Nagios Plugin to check a Redis server's client list

1. Returns counts of all connected clients, and in verbose mode unique clients address list
2. Checks all connected client addresses match expected address regex (optional)
3. Checks the the number of connected clients against warning/critical thresholds (optional)";


$VERSION = "0.3.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::Redis;
use Redis;
use Time::HiRes 'time';

my $expected;

%options = (
    %redis_options,
    "e|expected=s"     => [ \$expected,     "Allowed clients, raises critical if unauthorized clients are detected. Optional, regex" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive). Optional" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive). Optional" ],
);

@usage_order = qw/host port password expected warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$password   = validate_password($password) if $password;
if(defined($expected)){
    $expected = validate_regex($expected, "expected");
}
validate_int($precision, 1, 20, "precision");
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

my $redis = connect_redis(host => $host, port => $port, password => $password) || quit "CRITICAL", "failed to connect to redis server '$hostport'";

my $clients;
my $start_time = time;
try {
    $clients  = $redis->client_list;
};
catch_quit "failed to retrieve client list from redis server '$hostport'";
my $time_taken = sprintf("%0.${precision}f", time - $start_time);
vlog2 "client list retrieved in $time_taken secs";

my @clients = split("\n", $clients);
@clients or quit "UNKNOWN", "no clients returned, not even this code, must be an error, investigation required";

vlog2 "closing connection";
try {
    $redis->quit;
};

if($verbose > 2){
    print "\n";
    hr;
    print "#" . " " x 32 . "Client List\n";
    hr;
}
$msg = "";
my %authorized_clients;
my %unauthorized_clients;
my $client;
foreach(@clients){
    vlog3 $_;
    /^addr=($ip_regex):\d+\s+/ or quit "UNKNOWN", "failed to parse client list. $nagios_plugins_support_msg";
    $client = $1;
    if(defined($expected)){
        unless($client =~ $expected){
            $unauthorized_clients{$client} = 1;
        } else {
            $authorized_clients{$client} = 1;
        }
    } else {
        $authorized_clients{$client} = 1;
    }
}
hr if $verbose > 2;

my @authorized_clients   = sort keys %authorized_clients;
my @unauthorized_clients = sort keys %unauthorized_clients;
my $total_clients = scalar @authorized_clients + scalar @unauthorized_clients;

if(@unauthorized_clients){
    critical;
    plural @unauthorized_clients;
    $msg .= scalar @unauthorized_clients . " unauthorized client$plural";
    $msg .= ": @unauthorized_clients" if $verbose;
    $msg .= ", ";
}
if(@authorized_clients){
    plural @authorized_clients;
    $msg .= scalar @authorized_clients . " authorized client$plural";
    $msg .= ": @authorized_clients" if $verbose;
    $msg .= ", ";
}

plural $total_clients;
$msg .= "$total_clients total client$plural";
check_thresholds($total_clients);
$msg .= ", queried server in $time_taken secs | ";
$msg .= "total_clients=$total_clients";
msg_perf_thresholds();
$msg .= " authorized_clients=" . scalar @authorized_clients . " unauthorized_clients=" . scalar @unauthorized_clients . " query_time=${time_taken}s";

vlog2;
quit $status, $msg;
