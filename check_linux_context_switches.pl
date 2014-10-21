#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-04-13 14:18:12 +0100 (Wed, 13 Apr 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of context switches on the local Linux server. Designed to be called over NRPE";

$VERSION = "0.2";

use strict;
use warnings;
use Fcntl ':flock';
use Time::Local;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$critical = 0;
$warning  = 0;

my $last_count;
my $last_line;
my $last_timestamp;
my $now;
my $stat = "/proc/stat";
my $statefile = "/tmp/$progname.tmp";
my $total_context_switches;

%options = (
    "w|warning=i"   => [ \$warning,  "Warning  count threshold for context switches (optional, 0 = no threshold)" ],
    "c|critical=i"  => [ \$critical, "Critical count threshold for context switches (optional, 0 = no threshold)" ],
);

get_options();

if(defined($warning)){
    $warning  =~ /^\d+$/ || usage "invalid warning threshold given, must be a positive numeric integer";
}
if(defined($critical)){
    $critical =~ /^\d+$/ || usage "invalid critical threshold given, must be a positive numeric integer";
}

if($critical < $warning){
    $critical = $warning;
    vlog2 "setting critical to same as warning";
}

vlog_options "warning",     $warning;
vlog_options "critical",    $critical;
vlog_options "stat file",   $stat;
vlog_options "state file",  $statefile;
vlog2;

linux_only();
set_timeout();

my $fh;
open $fh, "$stat" or quit "UNKNOWN", "Error: failed to open '$stat': $!";

vlog3 "'$stat' contents:\n";
while(<$fh>){
    chomp;
    vlog3 $_;
    if(/^ctxt (\d+)$/){
        $total_context_switches = $1;
    }
}
vlog3;

($fh) || quit "CRITICAL", "Failed to find ctxt line in $stat";

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
    quit "UNKNOWN", "Last timestamp was in the future! Resetting...";
} elsif ($secs == 0){
    quit "UNKNOWN", "0 seconds since last run, aborting...";
}

my $context_switches_per_sec = ( $context_switches / $secs );

vlog2 "context switches per sec:            $context_switches_per_sec\n";

$context_switches_per_sec = int($context_switches_per_sec + 0.5);

my $status = "OK";
if($critical > 0 && $context_switches_per_sec >= $critical){
    $status = "CRITICAL";
} elsif ( $warning > 0 && $context_switches_per_sec >= $warning){
    $status = "WARNING";
}

quit $status, "$context_switches_per_sec context switches per second | 'context switches per second'=$context_switches_per_sec;$warning;$critical";
