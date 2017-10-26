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

our $tested_on = "Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

our $DESCRIPTION = "Nagios Plugin to check a Redis server's stats

1. Fetches one or more stats from specified Redis server. Defaults to fetching all stats
2. If specifying a single stat, checks the result matches expected value or warning/critical thresholds if specified
3. Outputs perfdata for all float value stats for graphing

$tested_on";

$VERSION = "0.7.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Redis;
use Redis;
use Time::HiRes 'time';

my $statlist;

my $check_replication_slave = 0;

my $expected;

%options = (
    %redis_options,
    "s|stats=s"        => [ \$statlist,     "Stats to retrieve, comma separated (default: all)" ],
    "e|expected=s"     => [ \$expected,     "Expected value for stat. Optional, only valid when a single stat is given" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold ra:nge (inclusive). Optional, only valid when a single stat is given" ],
);

if($progname eq "check_redis_version.pl"){
    $DESCRIPTION = "Nagios Plugin to check a Redis server's version";
    $statlist = "redis_version";
    $options{"e|expected=s"} = [ \$expected,     "Expected Redis version" ];
    delete $options{"s|stats=s"};
    delete $options{"w|warning=s"};
    delete $options{"c|critical=s"};
} elsif($progname eq "check_redis_slave.pl" or $progname eq "check_redis_replication.pl"){
    $check_replication_slave = 1;
    $DESCRIPTION = "Nagios Plugin to check a Redis slave and replication\n\n"
                 . "Checks:\n\n"
                 . "1. server is in 'slave' role\n"
                 . "2. link to master is up\n"
                 . "3. replication last I/O is within warning/critical thresholds\n"
                 . "4. checks if master sync is in progress (raises warning)\n"
                 . "\n" . $tested_on . "\n";
    $statlist = "role,master_host,master_port,master_link_status,master_last_io_seconds_ago,master_sync_in_progress";
    delete $options{"s|stats=s"};
    delete $options{"e|expected=s"};
    # This is the default in redis.conf
    my $default_last_replication = 60;
    $warning  = $default_last_replication / 2;
    $critical = $default_last_replication;
    $options{"w|warning=s"}  = [ \$warning,  "Warning  threshold ra:nge in secs for replication last I/O (inclusive, default: " . $default_last_replication/2 . ")" ],
    $options{"c|critical=s"} = [ \$critical, "Critical threshold ra:nge in secs for replication last I/O (inclusive, default: $default_last_replication)" ],
}

@usage_order = qw/host port password stats expected warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my @stats;
if(defined($statlist)){
    unless($statlist eq "all"){
        @stats = split(/\s*,\s*/, $statlist);
        foreach my $stat (@stats){
            $stat =~ /^([\w_-]+)$/;
            $stat = $1;
            vlog_option "stat", $stat;
        }
        @stats or usage "no valid stats specified";
    }
}
@stats = uniq_array @stats if @stats;
unless($check_replication_slave){
    if(scalar @stats > 1 and (defined($warning) or defined($critical) or defined($expected))){
        usage "cannot specify expected value or thresholds when specifying more than one statistic";
    }
}
$password   = validate_password($password) if $password;
$precision  = validate_int($precision, "precision", 1, 20);
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

# all the checks are done in connect_redis, will error out on failure
my ($redis, $hostport) = connect_redis(host => $host, port => $port, password => $password);

my $start_time = time;
my $info_hash;
try {
    $info_hash  = $redis->info
};
catch_quit "failed to retrieve stats from redis server '$hostport'";
my $time_taken = sprintf("%0.${precision}f", time - $start_time);
$info_hash or quit "UNKNOWN", "failed to retrieve stats (empty info hash returned) from redis server '$hostport'";
vlog2 "collected stats in $time_taken secs";

vlog2 "closing connection";
try {
    $redis->quit;
};

if($verbose > 2){
    print "\n";
    hr;
    print "#" . " " x 35 . "Stats\n";
    hr;
}
$msg = "";
my $msgperf = "";
my $stat_value;

sub process_stat($){
    defined($_[0]) or code_error "no stat passed to process_stat()";
    my $stat = $_[0];
    unless(defined($$info_hash{$stat})){
        quit "UNKNOWN", "no stat found: $stat";
    }
    $msg .= "$_=$$info_hash{$stat} ";
    vlog3 "$_=$$info_hash{$stat}";
    return if $stat =~ /port/;
    if(isFloat($$info_hash{$stat})){
        $msgperf .= "$stat=$$info_hash{$stat} ";
    } elsif(@stats and $$info_hash{$stat} =~ /^(\d+(?:\.\d+)?)(B|(?:K|M|G|T|P)(?:B)?)$/i){
        $$info_hash{$stat} = expand_units($1, $2);
        $msgperf .= "$stat=$$info_hash{$stat} ";
    }
}

if(@stats){
    if($check_replication_slave){
        unless(defined($$info_hash{"role"}) and $$info_hash{"role"} eq "slave"){
            quit "CRITICAL", "redis server is not configured as a slave (role=$$info_hash{role})";
        }
    }
    foreach(@stats){
        process_stat($_);
    }
} else {
    foreach(sort keys %$info_hash){
        process_stat($_);
    }
}
hr if $verbose > 2;

$msg =~ s/ $//;
$msgperf =~ s/ $//;
if(scalar @stats == 1 and isFloat($$info_hash{$stats[0]})){
    $msgperf .= msg_perf_thresholds(1);
}

if(scalar @stats == 1){
    if(defined($expected)){
        unless($$info_hash{$stats[0]} eq $expected){
            quit "CRITICAL", "$stats[0] returned '$$info_hash{$stats[0]}', expected '$expected'";
        }
    }
    if(defined($warning) or defined($critical)){
        if(isFloat($$info_hash{$stats[0]})){
            check_thresholds($$info_hash{$stats[0]});
        } else {
            quit "UNKNOWN", "non-float value returned for stat '$stats[0]', got '$$info_hash{$stats[0]}', cannot evaluate";
        }
    }
} elsif($check_replication_slave){
    $$info_hash{"role"} eq "slave" or quit "CRITICAL", "redis server is not configured as a slave";
    quit "CRITICAL", "no master host configured" unless($$info_hash{"master_host"});
    quit "CRITICAL", "no master port configured" unless($$info_hash{"master_port"});
    quit "CRITICAL", "master link is down (networking or authentication error?)" unless($$info_hash{"master_link_status"} eq "up");
    isInt($$info_hash{"master_sync_in_progress"}) or quit "UNKNOWN", "non-integer returned for master_sync_in_progress ('$$info_hash{master_sync_in_progress})' from redis server '$hostport'";
    $msg  = "$$info_hash{role} role, master link $$info_hash{master_link_status}, ";
    $msg .= "last replication I/O $$info_hash{master_last_io_seconds_ago} secs ago";
    check_thresholds($$info_hash{"master_last_io_seconds_ago"});
    if($$info_hash{"master_sync_in_progress"} != 0){
        warning;
        $msg .= ", MASTER SYNC IN PROGRESS";
    }
    $msg .= ", master $$info_hash{master_host}:$$info_hash{master_port}";
}

$msg .= ", queried server in $time_taken secs | ";
if($check_replication_slave){
    $msgperf = "master_last_io_seconds_ago=$$info_hash{master_last_io_seconds_ago}" . msg_perf_thresholds(1);
    $msgperf .= " master_sync_in_progress=$$info_hash{master_sync_in_progress}";
}
$msg .= "$msgperf " if $msgperf;
$msg .= "query_time=${time_taken}s";

vlog2;
quit $status, $msg;
