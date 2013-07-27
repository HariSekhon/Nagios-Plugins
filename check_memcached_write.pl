#!/usr/bin/perl -T
# nagios: -epn
#
#   Author: Hari Sekhon
#   Date: 2011-05-28 22:23:05 +0000 (Sat, 28 May 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Memcached server reads + writes

Checks:

1. writes a unique short lived key with dynamically generated value
2. reads back key
3. checks the returned value is identical to that written
4. records the read/write and overall timings to a given precision
5. compares timing of each read and write operation against warning/critical thresholds if given";

$VERSION = "0.8";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use HariSekhonUtils;
# Why am I using a socket connection instead of one of the libraries out there? Easy portability. Plus the text protocol isn't hard :)
use IO::Socket;
use Time::HiRes 'time';

my $default_port = 11211;
$port = $default_port;

$timeout_min = 1;
$timeout_max = 60;

my $default_precision = 8;
my $precision = $default_precision;

%options = (
    "H|host=s"      => [ \$host,        "Host to connect to" ],
    "P|port=s"      => [ \$port,        "Port to connect to (defaults to $default_port)" ],
    "w|warning=s"   => [ \$warning,     "Warning  threshold in seconds for each read/write operation (use float for milliseconds). Cannot be more than a third of the total plugin --timeout" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold in seconds for each read/write operation (use float for milliseconds). Cannot be more than a third of the total plugin --timeout" ],
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
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0, "max" => $timeout/3 } );
vlog2;

my $epoch  = time;
# there cannot be any space in the memcached key
my $key    = "nagios:HariSekhon:$progname:$epoch";
my @chars  = ("A".."Z", "a".."z", 0..9);
my $value  = "";
$value    .= $chars[rand @chars] for 1..20;
vlog_options "key",   $key;
vlog_options "value", $value;
my $flags  = 0;
my $bytes  = length($value);
vlog2;

set_timeout();

$status = "OK";

vlog2 "connecting to $host:$port";
my $start_time = time;
my $conn = IO::Socket::INET->new (
                                    Proto    => "tcp",
                                    PeerAddr => $host,
                                    PeerPort => $port,
                                 ) or quit "CRITICAL", "Failed to connect to '$host:$port': $!";
my $connect_time = time - $start_time;
vlog2 "OK connected in $connect_time secs\n";
$conn->autoflush(1) or quit "UNKNOWN", "failed to set autoflush on socket: $!";
vlog3 "set autoflush on";

# using add instead of set here to intentionally fail if the key is already present which it shouldn't be
my $memcached_write_cmd = "add $key $flags $timeout $bytes\r\n$value\r\n";
my $memcached_read_cmd  = "get $key\r\n"; 
vlog3 "\nsending write request: $memcached_write_cmd";
my $write_start_time = time;
print $conn $memcached_write_cmd or quit "CRITICAL", "failed to write memcached key/value on '$host:$port': $!";

my $line;
my $linecount = 0;
my $err_msg;
while (<$conn>){
    s/\r\n$//;
    vlog3 "memcached response: $_";
    s/\r$//;
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
    if(/^STORED$/){
        last;
    } else {
         quit "CRITICAL", "failed to store key/value to memcached on '$host:$port': $_";
    }
}
my $write_time_taken = time - $write_start_time;
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
my $read_time_taken = time - $read_start_time;
vlog2 "read request completed in $read_time_taken secs\n";

unless(defined($read_value)){
    quit "CRITICAL", "failed to find content back from memcached at '$host:$port', try running with -vv or -vvv to debug";
}

vlog2 "comparing read back value for key";
if($value eq $read_value){
    vlog2 "read back key has the same value '$read_value'";
} else {
    quit "CRITICAL", "read back for just written key '$key' mismatched! (original value: $value, read value: $read_value)";
}

my $time_taken = time - $start_time;
vlog2 "\ncompleted write + read back in $time_taken secs";
$time_taken = sprintf("%.${precision}f", $time_taken);

close $conn;
vlog2 "closed connection\n";

$write_time_taken = sprintf("%0.${precision}f", $write_time_taken);
$read_time_taken  = sprintf("%0.${precision}f", $read_time_taken);
$msg = "write key in $write_time_taken secs, read key in $read_time_taken secs, total time $time_taken";
check_thresholds($read_time_taken,1);
check_thresholds($write_time_taken);
$msg .= " | total_time=${time_taken}s write_time=${write_time_taken}s read_time=${read_time_taken}s";

quit $status, $msg;
