#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-05-28 22:23:05 +0000 (Sat, 28 May 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Memcached server via API read/write

Checks:

1. writes a unique ephemeral key with dynamically generated value
2. reads back same unique key
3. checks the returned value is identical to that written
4. records the read/write/delete timings and total time (including tcp connection and close) to a given precision
5. compares timing of each read/write/delete operation against warning/critical thresholds if given";

$VERSION = "0.9";

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

my $default_port = 11211;
$port = $default_port;

$timeout_min = 1;
$timeout_max = 60;

my $default_precision = 5;
my $precision = $default_precision;

%options = (
    "H|host=s"      => [ \$host,        "Host to connect to" ],
    "P|port=s"      => [ \$port,        "Port to connect to (default: $default_port)" ],
    "w|warning=s"   => [ \$warning,     "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds). Cannot be more than 1/4 of the total plugin --timeout (must increase timeout)" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds). Cannot be more than 1/4 of the total plugin --timeout (must increase timeout)" ],
    "precision=i"   => [ \$precision,   "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port warning critical precision/;
get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_int($precision, 1, 20, "precision");
unless($precision =~ /^(\d+)$/){
    code_error "precision is not a digit and has already passed validate_int()";
}
$precision = $1;
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0, "max" => $timeout/4 } );
vlog2;

my $epoch  = time;
# there cannot be any space in the memcached key
my $value  = random_alnum(20);
my $key    = "nagios:HariSekhon:$progname:$epoch:" . substr($value, 0, 10);
vlog_options "key",   $key;
vlog_options "value", $value;
my $flags  = 0;
my $bytes  = length($value);
vlog2;

set_timeout();

my $socket_timeout = sprintf("%.2f", $timeout / 4);
$socket_timeout = 1 if $socket_timeout < 1;
vlog2 "setting socket timeout to $socket_timeout secs as 1/4 of timeout since there are 3 more operations to do on socket\n";

$status = "OK";

vlog2 "connecting to $host:$port";
my $start_time = time;
my $ip = validate_resolvable($host);
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

# using add instead of set here to intentionally fail if the key is already present which it shouldn't be
my $memcached_write_cmd  = "add $key $flags $timeout $bytes\r\n$value\r\n";
my $memcached_read_cmd   = "get $key\r\n"; 
my $memcached_delete_cmd = "delete $key\r\n";
vlog3 "\nsending write request: $memcached_write_cmd";
my $write_start_time = time;
print $conn $memcached_write_cmd or quit "CRITICAL", "failed to write memcached key/value on '$host:$port': $!";

sub check_memcached_response($){
    my $_ = shift;
    my $err_msg;
    if(/ERROR/){
        if(/^ERROR$/){
            $err_msg = "unknown command sent to";
        } elsif(/CLIENT_ERROR/){
            $err_msg = "client error returned from";
        } elsif (/SERVER_ERROR/){
            $err_msg = "server error returned from";
        } else {
            $err_msg = "unknown error returned from";
        }
        quit "CRITICAL", "$err_msg memcached '$host:$port': '$_'";
    }
}

while (<$conn>){
    s/\r\n$//;
    vlog3 "memcached response: $_";
    s/\r$//;
    check_memcached_response($_);
    if(/^STORED$/){
        last;
    } else {
         quit "CRITICAL", "failed to store key/value to memcached on '$host:$port': $_";
    }
}
my $write_time_taken = sprintf("%0.${precision}f", time - $write_start_time);
vlog2 "write request completed in $write_time_taken secs\n";

vlog3 "\nsending read request: $memcached_read_cmd";
my $read_start_time = time;
print $conn $memcached_read_cmd or quit "CRITICAL", "failed to read back key/value from memcached on '$host:$port': $!";

my $read_value;
my $value_seen = 0;
my $value_regex = "^VALUE $key $flags $bytes\$";
vlog3 "value regex:       $value_regex\n";
while(<$conn>){
    s/\r\n$//;
    vlog3 "memcached response: $_";
    last if /END/;
    if($_ =~ /$value_regex/){
        $value_seen = 1;
        next;
    }
    quit "CRITICAL", "unexpected response returned instead of VALUE <key> <flags> <bytes>: $_" unless $value_seen;
    $read_value .= $_;
}
my $read_time_taken  = sprintf("%0.${precision}f", time - $read_start_time);
vlog2 "read request completed in $read_time_taken secs\n";

unless(defined($read_value)){
    quit "CRITICAL", "failed to find content back from memcached at '$host:$port', try running with -vv or -vvv to debug";
}

vlog2 "comparing read back value for key";
if($value eq $read_value){
    vlog2 "read back key has the same value '$read_value'\n";
} else {
    quit "CRITICAL", "read back for just written key '$key' mismatched! (original value: $value, read value: $read_value)";
}

my $delete_start_time = time;
print $conn $memcached_delete_cmd or quit "CRITICAL", "failed to delete memcached key/value on '$host:$port': $!";

while (<$conn>){
    s/\r\n$//;
    vlog3 "memcached response: $_";
    s/\r$//;
    check_memcached_response($_);
    if(/^DELETED$/){
        last;
    } else {
         quit "CRITICAL", "failed to store key/value to memcached on '$host:$port': $_";
    }
}
my $delete_time_taken = sprintf("%0.${precision}f", time - $delete_start_time);
vlog2 "delete request completed in $delete_time_taken secs\n";

close $conn;
vlog2 "closed connection\n";

my $time_taken = time - $start_time;
$time_taken = sprintf("%.${precision}f", $time_taken);
vlog2 "total time taken for connect => write => read => delete => close: $time_taken secs\n";

$msg  = "wrote key in $write_time_taken secs, ";
$msg .= "read key in $read_time_taken secs, ",
$msg .= "deleted key in $delete_time_taken secs, ",
$msg .= "total time $time_taken secs";
check_thresholds($delete_time_taken, 1);
check_thresholds($read_time_taken, 1);
check_thresholds($write_time_taken);
$msg .= " | total_time=${time_taken}s";
$msg .= " write_time=${write_time_taken}s";
msg_perf_thresholds();
$msg .= " read_time=${read_time_taken}s";
msg_perf_thresholds();
$msg .= " delete_time=${delete_time_taken}s";
msg_perf_thresholds();

quit $status, $msg;
