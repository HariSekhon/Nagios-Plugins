#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 21:08:10 +0000 (Sun, 17 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Redis server's client list

1. Returns counts of total connected clients and unique hosts
2. In verbose mode returns unique hosts address list
3. Checks all connected client host addresses match expected address regex (optional)
4. Checks the total number of connected clients against warning/critical thresholds (optional). There may be multiple client connections from each host and each one consumes a file descriptor on the server so it is the number of client connections rather than the number of hosts that are checked against thresholds

Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

$VERSION = "0.5.1";

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
    "e|expected=s"     => [ \$expected,     "Allowed client addresses, raises critical if unauthorized clients are detected. Optional, regex" ],
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
$precision  = validate_int($precision, "precision", 1, 20);
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

# all the checks are done in connect_redis, will error out on failure
my ($redis, $hostport) = connect_redis(host => $host, port => $port, password => $password);

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
my %authorized_hosts;
my %unauthorized_hosts;
my $client;
my $total_clients = 0;
foreach(@clients){
    vlog3 $_;
    /^(?:id=\d+\s+)?addr=(($ip_regex):\d+)\s+/ or quit "UNKNOWN", "failed to parse client list. $nagios_plugins_support_msg";
    $client = $1;
    $host   = $2;
    $total_clients++;
    if(defined($expected)){
        unless($host =~ $expected){
            $unauthorized_hosts{$host} = 1;
        } else {
            $authorized_hosts{$host} = 1;
        }
    } else {
        $authorized_hosts{$host} = 1;
    }
}
hr if $verbose > 2;

my @authorized_hosts   = sort keys %authorized_hosts;
my @unauthorized_hosts = sort keys %unauthorized_hosts;
my $total_hosts        = scalar @authorized_hosts + scalar @unauthorized_hosts;

plural $total_clients;
$msg  = "$total_clients total client$plural";
check_thresholds($total_clients);
plural $total_hosts;
$msg .= " from $total_hosts unique host$plural";

if(@unauthorized_hosts){
    critical;
    plural @unauthorized_hosts;
    $msg .= ", " . scalar @unauthorized_hosts . " UNAUTHORIZED host$plural";
    $msg .= ": @unauthorized_hosts" if $verbose;
}
if(@authorized_hosts){
    plural @authorized_hosts;
    $msg .= ", " . scalar @authorized_hosts . " authorized host$plural";
    $msg .= ": @authorized_hosts" if $verbose;
}

$msg .= ", queried server in $time_taken secs | ";
$msg .= "total_clients=$total_clients";
msg_perf_thresholds();
$msg .= " authorized_hosts=" . scalar @authorized_hosts . " unauthorized_hosts=" . scalar @unauthorized_hosts . " query_time=${time_taken}s";

vlog2 if is_ok;
quit $status, $msg;
