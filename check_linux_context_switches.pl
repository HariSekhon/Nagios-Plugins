#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-04-13 14:18:12 +0100 (Wed, 13 Apr 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of context switches on the local Linux server. Designed to be called over NRPE";

$VERSION = "0.3";

use strict;
use warnings;
use Fcntl ':flock';
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Math::Round;

my $last_count;
my $last_line;
my $last_timestamp;
my $now;
my $stat = "/proc/stat";
my $statefile = "/tmp/$progname.tmp";
my $total_context_switches;

%options = (
    %thresholdoptions,
);

get_options();

validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1});

vlog_option "stat file",   $stat;
vlog_option "state file",  $statefile;
vlog2;

linux_only();

set_timeout();

my $fh = open_file $stat;
#open $fh, "$stat" or quit "UNKNOWN", "Error: failed to open '$stat': $!";

vlog3 "'$stat' contents:\n";
while(<$fh>){
    chomp;
    vlog3 $_;
    if(/^ctxt\s+(\d+)$/){
        $total_context_switches = $1;
    }
}
vlog3;

defined($total_context_switches) || quit "CRITICAL", "failed to find context switches in $stat. $nagios_plugins_support_msg";

my $tmpfh;
vlog2 "opening state file '$statefile'\n";
if(-f $statefile){
    open $tmpfh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    open $tmpfh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
}
flock($tmpfh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";
$last_line = <$tmpfh>;
$now = time;
if($last_line){
    vlog3 "last line of state file: <$last_line>\n";
    if($last_line =~ /^(\d+)\s+(\d+)$/){
        $last_timestamp = $1;
        $last_count     = $2;
    } else {
        vlog2 "state file contents didn't match expected format\n";
    }
} else {
    vlog2 "no state file contents found\n";
}
if(not $last_timestamp or not $last_count){
        print "no counters in state file, resetting to current values\n\n";
        $last_timestamp = $now;
        $last_count     = $total_context_switches;
}
seek($tmpfh, 0, 0) or quit "UNKNOWN", "Error: seek failed: $!\n";
truncate($tmpfh, 0) or quit "UNKNOWN", "Error: failed to truncate '$statefile': $!";
print $tmpfh "$now $total_context_switches";

my $context_switches = $total_context_switches - $last_count;
my $secs             = $now - $last_timestamp;

vlog2 "context switches last count:         $last_count
context switches current count:      $total_context_switches
context switches since last check:   $context_switches

epoch now:                           $now
last run epoch:                      $last_timestamp
secs since last check:               $secs\n";

if($secs < 0){
    quit "UNKNOWN", "last timestamp was in the future! Resetting...";
} elsif ($secs == 0){
    quit "UNKNOWN", "0 seconds since last run, aborting...";
}

if($context_switches < 0){
    quit "UNKNOWN", "context switches = $context_switches < 0 in last $secs secs";
}

my $context_switches_per_sec = ( $context_switches / $secs );

vlog2 "context switches per sec:            $context_switches_per_sec\n";

$context_switches_per_sec = round($context_switches_per_sec);

$status = "OK";

$msg = "$context_switches_per_sec context switches per sec";
check_thresholds($context_switches_per_sec);
$msg .= " | 'context switches per sec'=$context_switches_per_sec";
msg_perf_thresholds();

quit $status, $msg;
