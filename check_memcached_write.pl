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

our $DESCRIPTION = "Nagios Plugin to check a Memcached server via API write => read

Checks:

1. writes a unique ephemeral key with dynamically generated value
2. reads back same unique key
3. checks the returned value is identical to that written
4. deletes the unique generated key, checks deleted occurred successfully
5. records the read/write/delete timings and total time (including tcp connection and close) to a given precision
6. compares timing of each read/write/delete operation against warning/critical thresholds if given

Tested on Memcached from around 2010/2011, plus 1.4.4, 1.4.25
";

$VERSION = "0.10.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
# Why am I using a socket connection instead of one of the libraries out there? Easy portability. Plus the text protocol isn't hard :)
use IO::Socket;
use Time::HiRes qw/time sleep/;

set_port_default(11211);
set_timeout_range(1, 60);

my $default_precision = 5;
my $precision = $default_precision;

my $server_name           = "memcached";
my $couchbase             = 0;
my $couchbase_replication = 0;
my $slave;
my $default_slave_delay   = 0.5;
my $slave_delay = $default_slave_delay;

if($progname =~ /couchbase/i){
    $couchbase = 1;
    $server_name = "couchbase";
    $DESCRIPTION =~ s/Memcached server via/Couchbase server via Memcached/;
    env_creds("COUCHBASE");
} else {
    env_creds("MEMCACHED");
}

%options = (
    %hostoptions,
    "w|warning=s"   => [ \$warning,     "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "precision=i"   => [ \$precision,   "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port warning critical precision/;

if($progname eq "check_couchbase_write_replication.pl"){
    $couchbase_replication = 1;
    $DESCRIPTION =~ s/^2\..*$/2. reads back the same unique key from the given replication slave after a configurable delay in secs (to allow for the write to replicate to the slave)/m;
    %options = (
        %options,
        "S|slave=s"       => [ \$slave,         "Couchbase slave host to read replicated write from to test replication" ],
        "slave-delay=s"   => [ \$slave_delay,   "Delay in secs before reading the key-value pair back from the Couchbase replication slave cluster (default: $default_slave_delay)" ],
    );
    @usage_order = qw/host port slave slave-delay warning critical precision/;
}

get_options();

$host = validate_host($host);
$port = validate_port($port);
$precision = validate_int($precision, "precision", 1, 20);
if($couchbase and $couchbase_replication){
    $slave = validate_host($slave, "slave");
    $slave_delay = validate_float($slave_delay, "slave delay", 0.02, 60); # In testing in a local Couchbase cluster 0.02 secs is the minimum time required for the replicated write check to work
    if($slave_delay > $timeout - 1){
        usage "slave delay cannot be set to more than (timeout - 1) secs, timeout is currently set to $timeout secs. Either increase --timeout or reduce --slave-delay";
    }
}
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );
vlog2;

my $epoch  = time;
# there cannot be any space in the memcached key
my $value  = random_alnum(20);
my $key    = "nagios:HariSekhon:$progname:$epoch:" . substr($value, 0, 10);
vlog_option "key",   $key;
vlog_option "value", $value;
my $flags  = 0;
my $bytes  = length($value);
vlog2;

set_timeout();

my $socket_timeout = sprintf("%.2f", $timeout / 4);
$socket_timeout = 1 if $socket_timeout < 1;
vlog2 "setting socket timeout to $socket_timeout secs as 1/4 of timeout since there are 3 more operations to do on socket\n";

$status = "OK";

my $start_time = time;

sub memcached_connect($){
    my $host = shift;
    vlog2 "connecting to $host:$port";
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
    vlog3 "set autoflush on\n";
    return $conn;
}
my $conn        = memcached_connect($host);
my $slave_conn  = memcached_connect($slave) if ($couchbase and $slave);

# using add instead of set here to intentionally fail if the key is already present which it shouldn't be
my $memcached_write_cmd  = "add $key $flags $timeout $bytes\r\n$value\r\n";
my $memcached_read_cmd   = "get $key\r\n";
my $memcached_delete_cmd = "delete $key\r\n";
vlog3 "sending write request: $memcached_write_cmd";
my $write_start_time = time;
print $conn $memcached_write_cmd or quit "CRITICAL", "failed to write $server_name key/value on '$host:$port': $!";

sub check_memcached_response($){
    my $response = shift;
    my $err_msg;
    if(/ERROR/){
        if($response =~ /^ERROR$/){
            $err_msg = "unknown command sent to";
        } elsif($response =~ /CLIENT_ERROR/){
            $err_msg = "client error returned from";
        } elsif ($response =~ /SERVER_ERROR/){
            $err_msg = "server error returned from";
        } else {
            $err_msg = "unknown error returned from";
        }
        quit "CRITICAL", "$err_msg $server_name '$host:$port': '$response'";
    }
}

while (<$conn>){
    s/\r\n$//;
    vlog3 "$server_name response: $_";
    s/\r$//;
    check_memcached_response($_);
    if(/^STORED$/){
        last;
    } else {
         quit "CRITICAL", "failed to store key/value to $server_name on '$host:$port': $_";
    }
}
my $write_time_taken = sprintf("%0.${precision}f", time - $write_start_time);
vlog2 "write request completed in $write_time_taken secs\n";

if($couchbase and $slave and $slave_delay){
    vlog2 sprintf("sleeping for %.2f secs before reading from couchbase slave", $slave_delay);
    sleep $slave_delay;
}

my $read_conn = $conn;
my $read_host = $host;
if($couchbase and $slave){
    $read_conn = $slave_conn;
    $read_host = $slave;
}
vlog3 "sending read request to $read_host:$port: $memcached_read_cmd";
my $read_start_time = time;
print $read_conn $memcached_read_cmd or quit "CRITICAL", "failed to read back key/value from $server_name on '$read_host:$port': $!";

my $read_value;
my $value_seen = 0;
my $value_regex = "^VALUE $key $flags $bytes\$";
vlog3 "value regex:       $value_regex\n";
while(<$read_conn>){
    s/\r\n$//;
    vlog3 "$server_name response: $_";
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
    quit "CRITICAL", "failed to read back key from '$read_host:$port'" . ( $couchbase_replication ? sprintf(" (either replication is broken or perhaps key/value didn't replicate within %.2f secs, consider increasing --slave-delay)", $slave_delay) : "");
}

vlog2 "comparing read back value for key";
if($value eq $read_value){
    vlog2 "read back key has the same value '$read_value'\n";
} else {
    quit "CRITICAL", "read back for just written key '$key' mismatched! (original value: $value, read value: $read_value)";
}

my $delete_start_time = time;
print $conn $memcached_delete_cmd or quit "CRITICAL", "failed to delete $server_name key/value on '$host:$port': $!";

while (<$conn>){
    s/\r\n$//;
    vlog3 "$server_name response: $_";
    s/\r$//;
    check_memcached_response($_);
    if(/^DELETED$/){
        last;
    } else {
         quit "CRITICAL", "failed to delete key/value to $server_name on '$host:$port': $_";
    }
}
my $delete_time_taken = sprintf("%0.${precision}f", time - $delete_start_time);
vlog2 "delete request completed in $delete_time_taken secs\n";

close $conn;
close $slave_conn if $slave_conn;
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
