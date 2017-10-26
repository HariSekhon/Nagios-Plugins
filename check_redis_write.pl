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

our $DESCRIPTION = "Nagios Plugin to check a Redis server is up and read/writable via API

Checks:

1. writes a new unique key with dynamically generated value
2. reads same key back
3. checks returned value is identical to the value generated and written
4. deletes the key
5. records the write/read/delete timings to a given precision for reporting and graphing
6. compares each operation's time taken against the warning/critical thresholds if given

Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

$VERSION = "0.6";

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

my $slave;
my $slave_port = $REDIS_DEFAULT_PORT;
my $slave_password;

my $default_slave_delay = 1;
my $slave_delay = $default_slave_delay;
my ($slave_delay_min, $slave_delay_max) = (0, 10);
my $check_deleted = 0;

%options = (
    %redis_options,
    %redis_options_database,
    "w|warning=s"        => [ \$warning,          "Warning  threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
    "c|critical=s"       => [ \$critical,         "Critical threshold in seconds for each read/write/delete operation (use float for milliseconds)" ],
);

if($progname eq "check_redis_write_replication.pl"){
    $DESCRIPTION =~ s/check a Redis server is up and read\/writable via API/check Redis replication via API write to master and read from slave/;
    $DESCRIPTION =~ s/(dynamically generated value)/$1 to master/;
    $DESCRIPTION =~ s/(reads same key back)/$1 from slave/;
    $DESCRIPTION =~ s/(generated and written)/$1 to master/;
    $DESCRIPTION =~ s/(deletes the key)/$1 on the master (optionally checks delete replicated to slave)/;
    %options = (
        %options,
        "S|slave=s"          => [ \$slave,            "Redis slave to read key back from to test replication (defaults to reading key back from master --host)" ],
        "slave-port=s"       => [ \$slave_port,       "Redis slave port to connect to (default: $REDIS_DEFAULT_PORT)" ],
        "slave-password=s"   => [ \$slave_password,   "Redis slave password. Defaults to using the same password as for the master if specified. If wanting to use password on master but not on slave, set this to a blank string" ],
        "slave-delay=s"      => [ \$slave_delay,      "Wait this many secs between write to master and read from slave to give the slave replica time to process the replication update, accepts floats (default: $default_slave_delay, min: $slave_delay_min, max: $slave_delay_max)" ],
        "slave-deleted"      => [ \$check_deleted,    "Additional optional check that the key was cleaned up and deleted on the slave (waits --slave-delay secs after delete)" ],
    );
}
@usage_order = qw/host port database password slave slave-port slave-password slave-delay slave-deleted warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$password   = validate_password($password) if defined($password);
if(defined($slave)){
    $slave         = validate_host($slave,      "slave");
    $slave_port    = validate_port($slave_port, "slave");
    if(defined($slave_password)){
        if($slave_password){
            $slave_password = validate_password($slave_password, "slave");
        }
    } elsif($password) {
        $slave_password = $password;
    }
    if($slave_delay){
        # If you have more than a 10 sec delay your Redis replication is probably quite problematic so not allowing user to set more than this
        $slave_delay = validate_float($slave_delay, "slave-read-delay", $slave_delay_min, $slave_delay_max);
    }
}
if($progname eq "check_redis_write_replication.pl"){
    defined($slave) or usage "slave not defined";
    ($host eq $slave) and usage "cannot specify same master and slave";
}
if(defined($database)){
    $database = validate_int($database, "database", 0, 15);
}
$precision = validate_int($precision, "precision", 1, 20);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );
vlog2;

my $epoch  = time;
my $value  = random_alnum(20);
my $key    = "HariSekhon:$progname:$host:$epoch:" . substr($value, 0, 10);
vlog_option "key",    $key;
vlog_option "value",  $value;
vlog2;
set_timeout();

$status = "OK";

# all the checks are done in connect_redis, will error out on failure
my ($redis, $hostport) = connect_redis(host => $host, port => $port, password => $password);
my ($redis_slave, $slavehostport);
if($slave){
    ($redis_slave, $slavehostport) = connect_redis(host => $slave, port => $slave_port, password => $slave_password);
}

if(defined($database)){
    vlog2 "selecting database $database on $hostport\n";
    try {
        $redis->select($database);
    };
    catch_quit "failed to change to database $database on $hostport";

    if($slave){
        vlog2 "selecting database $database on $slavehostport\n";
        try {
            $redis_slave->select($database);
        };
        catch_quit "failed to change to database $database on $slavehostport";
    }
}

# TODO: Could consider setting hashes, lists, sets etc later...
# Update: pub-sub is done under check_redis_publish_subscribe.pl

vlog2 "writing key to $hostport";
my $start_time   = time;
# XXX: should set expiry on this to something like 1 day but API doesn't support setex or expiry
try {
    $redis->set($key => $value);
};
catch_quit "failed to write key '$key' to redis server $hostport";
my $write_time   = time - $start_time;
$write_time      = sprintf("%0.${precision}f", $write_time);

my $hostport_read;
my $redis_read;
if($slave){
    if($slave_delay){
        plural $slave_delay;
        vlog2 "\nwaiting $slave_delay sec$plural before reading from slave $slavehostport";
        sleep $slave_delay;
    }
    $hostport_read = $slavehostport;
    $redis_read    = $redis_slave;
} else {
    $hostport_read = $hostport;
    $redis_read    = $redis;
}
vlog2 "\nreading key back from $hostport_read";
my $returned_value;
$start_time         = time;
try {
    $returned_value  = $redis_read->get($key) || quit "CRITICAL", "failed to get key '$key' from redis host $hostport_read";
};
catch_quit "failed to get key '$key' from redis host $hostport_read";
my $read_time       = time - $start_time;
$read_time          = sprintf("%0.${precision}f", $read_time);

# testing key content here to make sure that if there is anything suspicious we don't delete the key
vlog2 "testing key value returned";
vlog3 "key returned value '$value'";
if($value eq $returned_value){
    vlog3 "returned value matches value originally sent";
} else {
    quit "CRITICAL", "key '$key' returned wrong value '$returned_value', expected '$value' that was just written, not deleting key, INVESTIGATION REQUIRED";
}

vlog2 "\ndeleting key on $hostport";
$start_time      = time;
try {
    $redis->del($key) || quit "CRITICAL", "failed to delete key '$key' on redis host $hostport";
};
catch_quit "failed to delete key '$key' on redis host $hostport";
my $delete_time  = time - $start_time;
$delete_time     = sprintf("%0.${precision}f", $delete_time);

#my $key_exists_time;
if($slave and $check_deleted){
    try {
        plural $slave_delay;
        vlog2 "\nwaiting $slave_delay sec$plural before checking deleted on slave $slavehostport";
        vlog2 "checking key was deleted from slave";
        #$start_time = time;
        if($redis_slave->exists($key)){
            quit "CRITICAL", "delete was not replicated from master to slave within $slave_delay sec$plural";
        } else {
            #$key_exists_time = time - $start_time;
            #$key_exists_time = sprintf("%0.${precision}f", $key_exists_time);
            vlog "key does not exist on slave, delete replication succeeded";
        }
    };
    catch_quit "failed while checking if key was deleted from slave $hostport";
}

vlog2 "closing connection";
try {
    $redis->quit;
};

vlog2;
my $msg_perf = " |";
my $msg_thresholds = "s" . msg_perf_thresholds(1);
$msg_perf .= " write_time=${write_time}${msg_thresholds}";
$msg_perf .= " read_time=${read_time}${msg_thresholds}";
$msg_perf .= " delete_time=${delete_time}${msg_thresholds}";

if($slave){
    $msg  = "wrote key on master in $write_time secs, read key from slave in $read_time secs, deleted key from master in $delete_time secs";
    #$msg .= ", key existence check on slave took $key_exists_time secs" if $check_deleted;
    $msg .= ( $verbose ? " (master=$host, slave=$slave)" : "");
} else {
    $msg = "wrote key in $write_time secs, read key in $read_time secs, deleted key in $delete_time secs on redis server $host" . ( $verbose ? ":$port" : "");
}

check_thresholds($delete_time, 1);
check_thresholds($read_time, 1);
check_thresholds($write_time);

$msg .= $msg_perf;

quit $status, $msg;
