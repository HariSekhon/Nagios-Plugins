#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 00:22:17 +0000 (Sun, 17 Nov 2013)
#  Continuation an idea from Q3/Q4 2012, inspired by other similar NoSQL plugins developed a few years earlier
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check a Redis server

Checks:

1. writes a new unique key with dynamically generated value
2. reads same key back
3. checks returned value is identical to the value generated and written
4. deletes the key
5. records the write/read/delete timings to a given precision for reporting and graphing
6. compares each operation's time taken against the warning/critical thresholds if given";

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
$port = $default_port;

my $database;

my $default_precision = 5;
my $precision = $default_precision;

%options = (
    "H|host=s"         => [ \$host,         "Redis Host to connect to" ],
    "P|port=s"         => [ \$port,         "Redis Port to connect to (default: $default_port)" ],
    "d|database=s"     => [ \$database,     "Database to select (optional, will default to the default database 0)" ],
    #"u|user=s"         => [ \$user,         "User to connect with" ],
    #"p|password=s"     => [ \$password,     "Password to connect with" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "precision=i"      => [ \$precision,    "Number of decimal places for timings (default: $default_precision)" ],
);

@usage_order = qw/host port database user password warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
#$user       = validate_user($user);
#$password   = validate_password($password) if $password;
if(defined($database)){
    $database = validate_int($database, 0, 10000, "database");
}
validate_int($precision, 1, 20, "precision");
unless($precision =~ /^(\d+)$/){
    code_error "precision is not a digit and has already passed validate_int()";
}
$precision = $1;
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );
vlog2;

my $epoch  = time;
my $key    = "HariSekhon:$progname:$host:$epoch";
my @chars  = ("A".."Z", "a".."z", 0..9);
my $value  = "";
$value    .= $chars[rand @chars] for 1..20;
vlog_options "key",    $key;
vlog_options "value",  $value;
vlog2;
set_timeout();

$status = "OK";

my $hostport = $host . ( $verbose ? ":$port" : "" );
$host = validate_resolvable($host);
vlog2 "connecting to redis server '$hostport'";
my $redis;
try {
    $redis = Redis->new(server => "$host:$port");
};
catch_quit "failed to connect to redis server $hostport";
vlog2 "API ping";
$redis->ping or quit "CRITICAL", "API ping failed, not connected to server?";

if(defined($database)){
    vlog2 "selecting database $database";
    $redis->select($database);
}

# TODO: Could consider setting hashes, lists, sets, pub-sub etc later...

vlog2 "writing key";
my $start_time   = time;
$redis->set($key => $value) || quit "CRITICAL", "failed to write key '$key' to redis server '$hostport'";
my $write_time   = time - $start_time;
$write_time      = sprintf("%0.${precision}f", $write_time);

vlog2 "reading key back";
$start_time         = time;
my $returned_value  = $redis->get($key) || quit "CRITICAL", "key '$key' not found during get operation from redis host '$hostport'";
my $read_time       = time - $start_time;
$read_time          = sprintf("%0.${precision}f", $read_time);

# testing key content here to make sure that if there is anything suspicious we don't delete the key
vlog2 "testing key value returned";
vlog3 "key returned value '$value'";
if($value eq $returned_value){
    vlog3 "key returned expected value";
} else {
    quit "CRITICAL", "key '$key' returned wrong value '$returned_value', expected '$value' that was just written, not deleting key, INVESTIGATION REQUIRED";
}

vlog2 "deleting key";
$start_time      = time;
$redis->del($key) || quit "CRITICAL", "key '$key' not found during delete operation on redis host '$hostport'";
my $delete_time  = time - $start_time;
$delete_time     = sprintf("%0.${precision}f", $delete_time);

vlog2 "closing connection";
$redis->quit;

vlog2;
my $msg_perf = " | ";
my $msg_thresholds = "s" . msg_perf_thresholds(1);
$msg_perf .= " write_time=${write_time}${msg_thresholds}";
$msg_perf .= " read_time=${read_time}${msg_thresholds}";
$msg_perf .= " delete_time=${delete_time}${msg_thresholds}";

$msg = "wrote key in $write_time secs, read key in $read_time secs, deleted key in $delete_time secs on redis server $host" . ( $verbose ? ":$port" : "");

check_thresholds($delete_time, 1);
check_thresholds($read_time, 1);
check_thresholds($write_time);

$msg .= $msg_perf;

quit $status, $msg;
