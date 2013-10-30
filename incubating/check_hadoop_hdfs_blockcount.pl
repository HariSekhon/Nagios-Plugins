#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-28 23:26:28 +0000 (Mon, 28 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check Hadoop HDFS block counts per datanode or cluster wide

Checks:

1. Per DataNode block count against given --warning and --critical thresholds, reports highest datanode count

or

2. --cluster - Cluster wide block count against --warning and --critical thresholds

Calls hadoop / hdfs command.

Written in an hour as a toy on CDH 4.4, it's O(N) rather than O(1) execution time, on my (very long) todo list to rewrite this properly via API";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

my $default_hadoop_bin  = "hdfs";
my $legacy_hadoop_bin   = "hadoop";
my $hadoop_bin          = $default_hadoop_bin;

my $cluster = 0;

%options = (
    "cluster"       => [ \$cluster,     "Check the number of total blocks in the cluster instead of per datanode" ],
    "hadoop-bin=s"  => [ \$hadoop_bin,  "Path to 'hdfs' or 'hadoop' command if not in \$PATH" ],
    "w|warning=s"   => [ \$warning,     "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/cluster hadoop-bin warning critical/;
get_options();

# TODO: abstract + unify this with check_hadoop_dfs.pl
my $hadoop_bin_tmp;
unless($hadoop_bin_tmp = which($hadoop_bin)){
    if($hadoop_bin eq $default_hadoop_bin){
        vlog2 "cannot find command '$hadoop_bin', trying '$legacy_hadoop_bin'";
        $hadoop_bin_tmp = which($legacy_hadoop_bin) || quit "UNKNOWN", "cannot find command '$hadoop_bin' or '$legacy_hadoop_bin' in PATH ($ENV{PATH})";
    } else {
        quit "UNKNOWN", "cannot find command '$hadoop_bin' in PATH ($ENV{PATH})";
    }
}
$hadoop_bin = $hadoop_bin_tmp;
$hadoop_bin  =~ /\b\/?(?:hadoop|hdfs)$/ or quit "UNKNOWN", "invalid hadoop program '$hadoop_bin' given, should be called hadoop or hdfs!";
vlog_options "hadoop path", $hadoop_bin;

validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1 } );

vlog2;
set_timeout();

$status = "OK";

my $cmd  = "$hadoop_bin fsck / -files -blocks -locations";
vlog3 "cmd: $cmd";
open my $fh, "$cmd 2>&1 |";
my $returncode = $?;
my %datanode_blocks;
my $reported_total_blocks;
while(<$fh>){
    chomp;
    vlog3 "output: $_";
    /Permission denied/i and quit "CRITICAL", "Did you fail to run this as the hdfs superuser?. $_";
    if(/^\s*Total blocks(?:\s+\(validated\))?:\s+(\d+)/i){
        $reported_total_blocks = $1;
    }
    if(
        /^DEPRECATED:/i or
        /^\s*$/ or
        /^\.+$/ or
        /^Connecting to namenode/i or
        /^FSCK started/i or
        /^FSCK ended/i or
        /^Status:/i or
        #/^\s*Total/i or
        #/^\s*Minimally/i or
        /^\s+/ or
        /^The filesystem/i
        ){
            next;
        }
    # this is either a dir or
    # /path/to/filename 9 bytes, 1 block(s):  Under replicated BP-1762190244-$ip-1379972114581:blk_2571364567380249014_3972. Target Replicas is 3 but found 1 replica(s).
    /^\// and next;
    if(/^\d+\.\s+BP-\d+-$ip_regex-\d+:blk_-?[\d_]+\s+len=\d+\s+repl=\d+\s+\[($host_regex):\d+\]\s*$/i){
        if(defined($datanode_blocks{$1})){
            $datanode_blocks{$1} += 1;
        } else {
            $datanode_blocks{$1} = 1;
        }
        next;
    }
    quit "UNKNOWN", "unknown line detected: '$_'. $nagios_plugins_support_msg";
}
vlog3 "returncode: $returncode";
if($returncode ne 0){
    quit "CRITICAL", "hadoop fsck errored out with returncode $returncode. Run with -vvv to determine the cause";
}

unless(defined($reported_total_blocks)){
    quit "UNKNOWN", "failed to find the reported total block count, $nagios_plugins_support_msg";
}

my $highest_blockcount             = 0;
my $num_nodes_exceeding_blockcount = 0;
my $total_blocks                   = 0;
foreach(sort keys %datanode_blocks){
    my $block_count = $datanode_blocks{$_};
    $total_blocks += $block_count;
    if($verbose >= 2){
        print "\n";
        if($block_count > $thresholds{"critical"}){
            print "$_ block count $block_count > critical threshold $thresholds{critical}\n";
            $num_nodes_exceeding_blockcount++;
        } elsif($block_count > $thresholds{"warning"}){
            print "$_ block count $block_count > warning threshold $thresholds{warning}\n";
            $num_nodes_exceeding_blockcount++;
        }
        print "\n";
    }
    if($block_count > $highest_blockcount){
        $highest_blockcount = $block_count;
    }
}
if($reported_total_blocks != $total_blocks){
    quit "UNKNOWN", "mismatch in total blocks reported vs counted, $nagios_plugins_support_msg";
}
vlog2 "reported block count and total blocks counted match";
if($total_blocks == 0){
    quit "UNKNOWN", "zero total blocks detected, unless this is a brand new cluster, $nagios_plugins_support_msg";
}
vlog2 "total blocks: $total_blocks";
if($highest_blockcount == 0){
    quit "UNKNOWN", "no blocks detected per datanode, unless this is a brand new cluster, $nagios_plugins_support_msg";
}
vlog2 "highest node blocks: $highest_blockcount";

vlog2;

if($cluster){
    $msg = "$total_blocks total blocks in cluster";
} else {
    $msg = "$num_nodes_exceeding_blockcount datanodes with high block counts, highest block count $highest_blockcount";
}

check_thresholds($highest_blockcount);

if($cluster){
    $msg .= ", highest node block count $highest_blockcount";
} else {
    $msg .= ", $total_blocks total blocks in cluster";
}

$msg .= " | Cluster_block_count=$total_blocks";
msg_perf_thresholds() if $cluster;
$msg .= " DN_highest_block_count=$highest_blockcount";
msg_perf_thresholds() if !$cluster;

quit $status, $msg;
