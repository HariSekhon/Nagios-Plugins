#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-07-26 15:27:47 +0100 (Tue, 26 Jul 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Rewrote this code of mine more than a year later in my spare time in Nov 2012 to better leverage my personal library and extended it's features against ZooKeeper 3.4.1-1212694. This was prompted by studying for my CCAH CDH4 (wish I had also picked up the earlier versions 1-2 years before like a couple of my colleagues did, the syllabus was half the size!).
# Finally got round to finishing it on the plane ride back from San Francisco / Cloudera Jan 26 2013, tested against my local version 3.4.5-1392090, built on 09/30/2012 17:52 GMT

$DESCRIPTION = "Nagios Plugin to monitor Zookeeper

Checks:

1. ruok - checks to see if ZooKeeper reports itself as ok
2. isro - checks to see if ZooKeeper is still writable
3. mode - checks to see if ZooKeeper is in the proper mode (leader/follower) vs standalone
4. number of outstanding requests
5. avg latency - the average latency reported by ZooKeeper is within the thresholds given. Optional
6. stats - full stats breakdown
7. also reports ZooKeeper version

Requires ZooKeeper 3.4 onwards due to isro and mntr 4lw checks only being available from 3.4+.

Tested on Apache ZooKeeper 3.4.5, 3.4.6, 3.4.8, 3.4.11 and on Cloudera, Hortonworks and MapR.
";

$VERSION = "0.8.3";

use strict;
use warnings;
use Fcntl ':flock';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ZooKeeper;
use Math::Round;
use Time::HiRes 'time';

my $standalone;
my $outstanding_requests = "0,10";

%options = (
    "H|host=s"                 => [ \$host,                 "ZooKeeper Host to connect to (\$ZOOKEEPER_HOST, \$HOST)" ],
    "P|port=s"                 => [ \$port,                 "ZooKeeper Client Port to connect to (defaults to $ZK_DEFAULT_PORT, set to 5181 for MapR, \$ZOOKEEPER_PORT, \$PORT)" ],
    "o|outstanding-requests=s" => [ \$outstanding_requests, "Number of outstanding requests thresholds (\"[warn,]crit\"), defaults to 0,10 => warning if greater than zero, critical if greater than 10 - should be zero under normal circumstances, otherwise requests are backing up and could cause coordination problems" ],
    "w|warning=s"              => [ \$warning,              "Warning  threshold or ran:ge (inclusive) for avg latency"  ],
    "c|critical=s"             => [ \$critical,             "Critical threshold or ran:ge (inclusive) for avg latency" ],
    "s|standalone"             => [ \$standalone,           "OK if mode is standalone (by default expects leader/follower mode as part of a proper ZooKeeper cluster with quorum)" ],
);
splice @usage_order, 7, 0, qw/outstanding-requests standalone warning critical/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(undef, undef, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "outstanding requests", $outstanding_requests);
validate_thresholds(undef, undef, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 });

set_timeout();

$status = "OK";

$msg = "ZooKeeper ";

# Check 1 - does ZooKeeper report itself as OK?
zoo_cmd "ruok", $timeout / 5;
my $response = <$zk_conn>;
defined($response) or $response = "";
vlog2 "ruok response  = '$response'\n";
if($response ne "imok"){
    critical;
    $msg .= "ruok = '$response' (expected: 'imok'), ";
}

# Check 2 - is ZooKeeper read-write or has a problem occurred with Quorum or similar?
zoo_cmd "isro", $timeout / 5;
# rw response or quit CRITICAL "ZooKeeper is not read-write (possible network partition?";
$response = <$zk_conn>;
defined($response) or $response = "";
vlog2 "isro response  = '$response'\n";
if($response ne "rw"){
    critical;
    $msg .= "isro = '$response' (expected: 'rw'), ";
}

# Check 3 - check the number of connections and path/total watches
#
zoo_cmd "wchs", $timeout / 5;
my %wchs;
vlog3 "\nOutput from 'wchs':";
while(<$zk_conn>){
    chomp;
    vlog3 "=> $_";
    if(/(\d+) connections watching (\d+) paths/i){
        $wchs{"connections"}   = $1;
        $wchs{"paths"}         = $2;
    } elsif(/Total watches:\s*(\d+)/i){
        $wchs{"total_watches"} = $1;
    }
}
foreach(( 'connections', 'paths', 'total_watches' )){
    defined($wchs{"$_"}) ? vlog2 "wchs $_ = $wchs{$_}" : quit "failed to determine $_ from output of wchs";
}
vlog2;

## Obsolete, get all of this from mntr except for Zxid which isn't worth the extra round trip
## Check 4 - Stats & Mode
## Zookeeper version: 3.4.1-1212694, built on 12/10/2011 00:05 GMT
## Latency min/avg/max: 0/2/1306
## Received: 422906808
## Sent: 422913035
## Outstanding: 0
## Zxid: 0x10921c222
## Mode: follower
## Node count: 52587
#my %stats = (
#    "Received"          => undef,
#    "Sent"              => undef,
#    "Outstanding"       => undef,
#    "Node count"        => undef,
#);
#my %srvr = (
#    "Zookeeper version" => undef,
#    "Latency min"       => undef,
#    "Latency avg"       => undef,
#    "Latency max"       => undef,
#    "Zxid"              => undef,
#    "Mode"              => undef,
#    %stats
#);
#
#zoo_cmd "srvr";
#my $line;
#my $linecount = 0;
#my $err_msg;
#my $zookeeper_version;
#my $latency_stats;
#my $mode;
#vlog3 "\nOutput from 'srvr':";
#while (<$zk_conn>){
#    chomp;
#    $line = $_;
#    #vlog3 "processing line: '$_'";
#    vlog3 "=> $_";
#    if($line =~ /not currently serving requests/){
#        quit "CRITICAL", $line;
#    }
#    if($line =~ /ERROR/i){
#        quit "CRITICAL", "unknown error returned from zookeeper on '$host:$port': '$line'";
#    }
#    $linecount++;
#    if($line =~ /^Zookeeper version:\s*(.+)?\s*$/i){
#        $srvr{"Zookeeper version"} = $1;
#    } elsif($line =~ /^Latency min\/avg\/max\s*:?\s*(\d+)\/(\d+)\/(\d+)\s*$/i){
#        $srvr{"Latency min"} = $1;
#        $srvr{"Latency avg"} = $2;
#        $srvr{"Latency max"} = $3;
#    } elsif($line =~ /^Mode:\s*(.+?)\s*$/i){
#        $srvr{"Mode"} = $1;
#    } elsif($line =~ /^Zxid:\s*(.+?)\s*$/i){
#        $srvr{"Zxid"} = $1;
#    } else {
#        foreach(sort keys %stats){
#            #vlog "checking for stat $_";
#            if($line =~ /^$_:\s*(\d+)\s*$/i){
#                #vlog2 "found $_";
#                $srvr{$_} = $1;
#                last;
#            }
#        }
#    }
#}
#vlog2;
#
#foreach my $key (sort keys %srvr){
#    defined($srvr{$key}) ? vlog2 "srvr $key = $srvr{$key}" : quit "UNKNOWN", "failed to determine $key";
#    if(grep {$key eq $_} keys %stats or $key =~ /Latency/){
#        $srvr{$key} =~ /^\d+$/ or quit "UNKNOWN", "invalid value found for srvr $key '$srvr{key}'";
#    }
#}
##vlog2 "got response" if ($linecount > 0);
#vlog2;

# Check 5 - Advanced Stats (also exposed via JMX)
#
# mntr
# zk_version      3.4.3-1240972, built on 02/06/2012 10:48 GMT
# zk_avg_latency  0
# zk_max_latency  18
# zk_min_latency  0
# zk_packets_received     1647
# zk_packets_sent 1675
# zk_outstanding_requests 0
# zk_server_state standalone
# zk_znode_count  19
# zk_watch_count  14
# zk_ephemerals_count     2
# zk_approximate_data_size        586
# zk_open_file_descriptor_count   255
# zk_max_file_descriptor_count    10240
my %mntr = (
    "zk_version"                     => undef,
    "zk_avg_latency"                 => undef,
    "zk_max_latency"                 => undef,
    "zk_min_latency"                 => undef,
    "zk_packets_received"            => undef,
    "zk_packets_sent"                => undef,
    "zk_outstanding_requests"        => undef,
    "zk_server_state"                => undef,
    "zk_znode_count"                 => undef,
    "zk_watch_count"                 => undef,
    "zk_ephemerals_count"            => undef,
    "zk_approximate_data_size"       => undef,
    "zk_open_file_descriptor_count"  => undef,
    "zk_max_file_descriptor_count"   => undef,
);
zoo_cmd "mntr", $timeout / 5;
vlog3 "\nOutput from 'mntr':";
my $found_mntr_output = 0;
while(<$zk_conn>){
    chomp;
    my $line = $_;
    vlog3 "=> $line";
    foreach(keys %mntr){
        if($line =~ /^\s*$_\s+(.+?)\s*$/){
            $found_mntr_output = 1;
            $mntr{$_} = $1;
            last;
        }
    }
}
vlog3;

unless($found_mntr_output){
    zoo_cmd "envi", $timeout / 5;
    while(<$zk_conn>){
        chomp;
        my $line = $_;
        vlog3 "=> $line";
        if($line =~ /^zookeeper.version=(\d+\.\d+)/){
            if($1 < 3.4){
                vlog3;
                quit "UNKNOWN", "ZooKeeper version < 3.4, 'mntr' information not available. This plugin does not support ZooKeeper < 3.4";
            }
        }
    }
}

foreach(sort keys %mntr){
    if(defined($mntr{$_})){
        vlog2 "mntr $_ = $mntr{$_}"
    } else {
        quit "UNKNOWN", "failed to determine $_ from mntr. $nagios_plugins_support_msg_api";
    }
    next if ($_ eq "zk_version" or $_ eq "zk_server_state");
    # In the ZooKeeper code base these two stats are set to -1 if ZooKeeper is unable to determine these metrics
    if($_ eq "zk_open_file_descriptor_count" or $_ eq "zk_max_file_descriptor_count"){
        if($mntr{$_} == -1){
            $mntr{$_} = "N/A";
            next;
        }
    } elsif($_ eq "zk_min_latency"){
        # this can appear, handle with warning below
        #$mntr{"zk_min_latency"} = -681;
        if($mntr{$_} < 0){
            warning;
            $msg .= "min latency < 0! (run 'srst' command on ZooKeeper to reset stats to fix). ";
            # invalid reset to N/A
            $mntr{$_} = "N/A";
            next;
        }
    }
    isFloat($mntr{$_}, "negative allowed") or quit "UNKNOWN", "invalid value found for mntr $_ '$mntr{$_}'";
}
vlog2;

# Stat call could go here if I wanted to list clients

#close $zk_conn and
#vlog2 "closed connection\n";

foreach(sort keys %mntr){
    defined($mntr{$_}) or quit "CRITICAL", "$_ was not found in output from zookeeper on '$host:$port'";
}

###############################
# TODO: abstract out this store state block to my personal library since I use it in a few pieces of code
my $tmpfh;
my $statefile = "/tmp/$progname.$host.$port.state";
vlog2 "opening state file '$statefile'\n";
my $new_statefile = 0;
if(-f $statefile){
    open $tmpfh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    $new_statefile = 1;
    open $tmpfh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
}
flock($tmpfh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";
my $last_line = <$tmpfh>;
my $now = time;
my $last_timestamp;
my %last_stats;
if($last_line){
    vlog2 "last line of state file: <$last_line>\n";
    if($last_line =~ /^(\d+(?:\.\d+)?)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s*$/x){
        $last_timestamp                         = $1;
        $last_stats{"zk_outstanding_requests"}  = $2,
        $last_stats{"zk_packets_received"}      = $3,
        $last_stats{"zk_packets_sent"}          = $4,
    } else {
        vlog2 "state file contents didn't match expected format\n";
    }
} else {
    vlog2 "no state file contents found\n";
}
my $missing_stats = 0;
unless(defined($last_timestamp)){
    vlog2 "last timestamp was not found in state file (" . ($last_line ? "invalid format" : "empty contents") . ")";
    $missing_stats = 1;
}
foreach(qw/zk_outstanding_requests zk_packets_received zk_packets_sent/){
    unless(defined($last_stats{$_}) and $last_stats{$_} =~ /^\d+$/){
        vlog2 "'$_' stat was not found in state file (" . ($last_line ? "invalid format" : "empty contents") . ")";
        $missing_stats = 1;
    }
}
if($missing_stats){
    if($new_statefile){
        vlog2 "no state file existed, this run will populate initial state - results will be available from next run\n";
    } else {
        vlog2 "missing or incorrect stats in state file, resetting to current values\n";
    }
    $last_timestamp = $now;
}
seek($tmpfh, 0, 0)  or quit "UNKNOWN", "Error: seek failed: $!\n";
truncate($tmpfh, 0) or quit "UNKNOWN", "Error: failed to truncate '$statefile': $!";
print $tmpfh "$now ";
my @stats = (
    "zk_outstanding_requests",
    "zk_packets_received",
    "zk_packets_sent",
);
foreach(@stats){
    print $tmpfh "$mntr{$_} ";
}
close $tmpfh;
###############################

my $secs = $now - $last_timestamp;

my %stats_diff;
if($secs < 0){
    quit "UNKNOWN", "Last timestamp was in the future! Resetting...";
#} elsif ($secs == 0){
#    quit "UNKNOWN", "0 seconds since last run, aborting...";
} elsif ($secs >= 1){
    foreach(@stats){
        #next if ($_ eq "Node count");
        $stats_diff{$_} = round(($mntr{$_} - $last_stats{$_} ) / $secs);
        if ($stats_diff{$_} < 0) {
            quit "UNKNOWN", "recorded stat $_ is higher than current stat, resetting stats";
        }
    }

    if($verbose >= 2){
        print "epoch now:                           $now\n";
        print "last run epoch:                      $last_timestamp\n";
        print "secs since last check:               $secs\n\n";
        printf "%-30s %-20s %-20s %-20s\n", "Stat", "Current", "Last", "Diff/sec";
        foreach(sort keys %stats_diff){
            printf "%-30s %-20s %-20s %-20s\n", $_, $mntr{$_}, $last_stats{$_}, $stats_diff{$_};
        }
        print "\n\n";
    }
}

#sub compare_zooresults {
#    ($srvr{$_[0]} eq $mntr{$_[1]}) or quit "UNKNOWN", "inconsistency between srvr $_[0] ('$srvr{$_[0]}') and mntr $_[1] ('$mntr{$_[1]}')";
#}
#
#compare_zooresults "Zookeeper version", "zk_version";
#compare_zooresults "Mode", "zk_server_state";
## This would introduce a race consition of these things changing in between calls. The above 2 should never fluctuate
##compare_zooresults "Latency min", "zk_min_latency";
##compare_zooresults "Latency avg", "zk_avg_latency";
##compare_zooresults "Latency max", "zk_max_latency";

unless(grep { $_ eq $mntr{"zk_server_state"} } @zk_valid_states){
    critical;
    $mntr{"zk_server_state"} = uc $mntr{"zk_server_state"};
}
if($mntr{"zk_server_state"} eq "standalone"){
    unless($standalone){
        $mntr{"zk_server_state"} = uc $mntr{"zk_server_state"};
        warning;
    }
}

$msg .= "Mode $mntr{zk_server_state}, ";
$msg .= "avg latency $mntr{zk_avg_latency}";
check_thresholds($mntr{"zk_avg_latency"});
$msg .= ", outstanding requests $mntr{zk_outstanding_requests}";
check_thresholds($mntr{"zk_outstanding_requests"}, undef, "outstanding requests");
#$msg .= "Latency min/avg/max $mntr{zk_min_latency}/$mntr{zk_avg_latency}/$mntr{zk_max_latency}, ";
$msg .= ", version $mntr{zk_version}";
if($secs >= 1){
    $msg .= " |";
    foreach(sort keys %stats_diff){
        $msg .= " '$_/sec'=$stats_diff{$_}";
    }
    foreach(sort keys %mntr){
        next if ($_ eq "zk_version" or $_ eq "zk_server_state");
        $msg .= " $_=$mntr{$_}";
        msg_perf_thresholds(undef, undef, "outstanding requests") if $_ eq "zk_outstanding_requests";
    }
    foreach(sort keys %wchs){
        $msg .= " wchs_$_=$wchs{$_}";
    }
} else {
    if($new_statefile){
        $msg .= " (state file wasn't found, stats will be available from next run)";
    } elsif($missing_stats){
        $msg .= " (missing or incorrect state file stats, should have been reset now and available from next run)";
    } elsif(not $secs >= 1 and not $missing_stats){
        $msg .= " (less than 1 sec since last run, won't output stats on this run since they wouldn't be an accurate delta)";
    } else {
        $msg .= " (stats not available, will attempt to re-set state this run to return correct stats on next run, if that doesn't fix it: $nagios_plugins_support_msg)";
    }
}
quit $status, $msg;
