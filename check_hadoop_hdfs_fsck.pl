#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-28 23:26:28 +0000 (Mon, 28 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to parse and alert on Hadoop FSCK output

Checks the status of the HDFS FSCK output and optionally one of the following against warning/critical thresholds:

- Time in secs since last fsck (recommend setting thresholds to > 86400 ie once a day)
- Time taken for FSCK in secs
- Max number of HDFS blocks (affects NameNode)
- Optionally outputs some more HDFS stats with perfdata for graphing (see also check_hadoop_replication.pl)

In order to constrain the runtime of this plugin you must run the Hadoop FSCK separately and have this plugin check the output file results. Recommend you do not use any extra switches as it'll enlarge the output and slow down the plugin by forcing it to parse all the extra noise. As the 'hdfs' user run this periodically (via cron):

hdfs fsck / &> /tmp/hdfs-fsck.log.tmp

# make sure not to trim too much though as we still want to find status field
tail -n 30 /tmp/hdfs-fsck.log.tmp > /tmp/hdfs-fsck.log

Then have the plugin check the results separately (the tail stops the log getting too big and slowing the plugin down if there is lots of corruption/missing blocks which will end up enlarging the output - it gives us just the bit we need, which are the stats at the end):

./check_hadoop_fsck.pl -f /tmp/hdfs-fsck.log

Tested on Hortonworks HDP 2.1, 2.2, 2.3, 2.6 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.4.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use POSIX 'floor';
use Time::Local;

my $file;
my $last_fsck  = 0;
my $fsck_time  = 0;
my $max_blocks = 0;
my $stats;

%options = (
    "f|file=s"   => [ \$file,       "HDFS FSCK result file" ],
    "last-fsck"  => [ \$last_fsck,  "Check time in secs since last HDFS FSCK against thresholds" ],
    "fsck-time"  => [ \$fsck_time,  "Check HDFS FSCK time taken against thresholds" ],
    "max-blocks" => [ \$max_blocks, "Check max HDFS blocks against thresholds" ],
    "stats"      => [ \$stats,      "Output HDFS stats" ],
    %thresholdoptions,
);
@usage_order = qw/file last-fsck fsck-time max-blocks stats warning critical/;

get_options();

$file or usage "hdfs fsck result file not specified";
$file = validate_file($file);
if($last_fsck + $fsck_time + $max_blocks > 1){
    usage "cannot specify more than one of --last-fsck / --max-fsck-time / --max-blocks";
}
if($last_fsck or $fsck_time or $max_blocks){
    validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1 } );
}

vlog2;
set_timeout();

$status = "OK";

my $fh = open_file $file;
my %hdfs;
while(<$fh>){
    chomp;
    vlog3 "file: $_";
    /Permission denied/i and quit "CRITICAL", "Did you fail to run this as the hdfs superuser? $_";
    if(/^\// and not /\bStatus\s*:/){
        next;
    # this can end up being mixed on a line with a file such as
    # 2017-11-06 15:29:24 +0100  file: /tmp/test.txt: MISSING 1 blocks of total size 8 B.Status: CORRUPT
    } elsif(/\bStatus\s*:\s*(\w+)/){
        $hdfs{"status"} = $1;
    } elsif(/^\s*Total size:\s*(\d+)/){
        $hdfs{"size"} = $1;
    } elsif(/^\s*Total dirs:\s*(\d+)/){
        $hdfs{"dirs"} = $1;
    } elsif(/^\s*Total files:\s*(\d+)/){
        $hdfs{"files"} = $1;
    } elsif(/^\s*Total blocks(?:\s*\(validated\))?:\s*(\d+)/i){
        $hdfs{"blocks"} = $1;
    } elsif(/^\s*Minimally replicated blocks:\s*(\d+)\s*\((\d+\.\d+)\s*%\)/){
        $hdfs{"min_rep_blocks"}    = $1;
        $hdfs{"min_rep_blocks_pc"} = $2;
    } elsif(/^\s*Over-replicated blocks:\s*(\d+)\s*\((\d+\.\d+)\s*%\)/){
        $hdfs{"over_rep_blocks"}    = $1;
        $hdfs{"over_rep_blocks_pc"} = $2;
    } elsif(/^\s*Under-replicated blocks:\s*(\d+)\s*\((\d+\.\d+)\s*%\)/){
        $hdfs{"under_rep_blocks"}    = $1;
        $hdfs{"under_rep_blocks_pc"} = $2;
    } elsif(/^\s*Mis-replicated blocks:\s*(\d+)\s*\((\d+\.\d+)\s*%\)/){
        $hdfs{"mis_rep_blocks"}    = $1;
        $hdfs{"mis_rep_blocks_pc"} = $2;
    } elsif(/^\s*Default replication factor:\s*(\d+)/){
        $hdfs{"default_rep_factor"} = $1;
    } elsif(/^\s*Average block replication:\s*(\d+\.\d+)/){
        $hdfs{"avg_block_rep"} = $1;
    } elsif(/^\s*Corrupt blocks:\s*(\d+)/){
        $hdfs{"corrupt_blocks"} = $1;
    } elsif(/^\s*Missing replicas:\s*(\d+)\s*\((\d+\.\d+)\s*%\)/){
        $hdfs{"missing_replicas"}    = $1;
        $hdfs{"missing_replicas_pc"} = $2;
    } elsif(/^\s*Missing replicas:\s*(\d+)/){
        $hdfs{"missing_replicas"}    = $1;
        # will sprintf to zero in --stats, just leave the graph flatlined for now
        #$hdfs{"missing_replicas_pc"} = "N/A";
        $hdfs{"missing_replicas_pc"} = 0;
    } elsif(/^\s*Number of data-nodes:\s*(\d+)/){
        $hdfs{"num_datanodes"} = $1;
    } elsif(/^\s*Number of racks:\s*(\d+)/){
        $hdfs{"num_racks"} = $1;
    } elsif(/^FSCK ended at (\w+\s+(\w+)\s+(\d+)\s+(\d{1,2}):(\d{2}):(\d{2}) \w+ (\d+)) in (\d+) milliseconds/){
        $hdfs{"fsck_ended"} = $1;
        $hdfs{"fsck_time"}  = floor($8 / 1000);
        my $month = $2;
        my $day   = $3;
        my $month_int = month2int($month);
        my $hour  = $4;
        my $min   = $5;
        my $sec   = $6;
        my $year  = $7;
        $hdfs{"fsck_age"}   = timelocal($sec, $min, $hour, $day, $month_int, $year-1900) || code_error "failed to convert fsck ended time to secs";
        $hdfs{"fsck_age"}   = time - floor($hdfs{"fsck_age"});
        if($hdfs{"fsck_age"} < 0){
            quit "UNKNOWN", "hdfs fsck time is in the future! NTP issue, are you checking this on the same server fsck was run on? $nagios_plugins_support_msg";
        }
    } elsif(/The filesystem under path .+ is (\w+)/){
        $hdfs{"final_status"} = $1;
    }
    /error/i and quit "CRITICAL", "error detected: $_";
#    quit "UNKNOWN", "unknown line detected: '$_'. $nagios_plugins_support_msg";
}

foreach(qw/status size dirs files blocks min_rep_blocks min_rep_blocks_pc over_rep_blocks over_rep_blocks_pc under_rep_blocks under_rep_blocks_pc mis_rep_blocks mis_rep_blocks_pc default_rep_factor avg_block_rep corrupt_blocks missing_replicas missing_replicas_pc num_datanodes num_racks fsck_ended fsck_time fsck_age final_status/){
    unless(defined($hdfs{$_})){
        quit "UNKNOWN", "hdfs $_ not found. $nagios_plugins_support_msg";
    }
}
critical unless $hdfs{"status"} eq "HEALTHY";
if($hdfs{"status"} ne $hdfs{"final_status"}){
    quit "UNKNOWN", "hdfs status mismatch ('$hdfs{status}' vs '$hdfs{final_status}'). $nagios_plugins_support_msg";
}

if($hdfs{"blocks"} == 0){
    quit "UNKNOWN", "zero total blocks detected, unless this is a brand new cluster, $nagios_plugins_support_msg";
}

$msg = "hdfs status: $hdfs{status}";
$msg .= sprintf(", last checked %d secs ago", $hdfs{"fsck_age"});
if($last_fsck){
    check_thresholds($hdfs{"fsck_age"});
}
$msg .= sprintf(" [%s] in %d secs", $hdfs{"fsck_ended"}, $hdfs{"fsck_time"});
if($fsck_time){
    check_thresholds($hdfs{fsck_time});
}
if($verbose or $max_blocks){
    $msg .= ", total blocks=$hdfs{blocks}";
    if($max_blocks){
        check_thresholds($hdfs{"blocks"});
    }
}
my $msg2;
if($stats){
    $msg2 = sprintf(", size=%s dirs=%d files=%d min_replicated_blocks=%d 'min_replicated_blocks_%%'=%.2f%% over_rep_blocks=%d 'over_rep_blocks_%%'=%.2f%% under_rep_blocks=%d 'under_rep_blocks_%%'=%.2f%% mis_rep_blocks=%d 'mis_rep_blocks_%%'=%.2f%% default_rep_factor=%d avg_block_rep=%.2f corrupt_blocks=%d missing_replicas=%d 'missing_replicas_%%'=%.2f%% num_datanodes=%d num_racks=%d",
    human_units($hdfs{"size"}),
    $hdfs{"dirs"}, $hdfs{"files"},
    $hdfs{"min_rep_blocks"},
    $hdfs{"min_rep_blocks_pc"},
    $hdfs{"over_rep_blocks"},
    $hdfs{"over_rep_blocks_pc"},
    $hdfs{"under_rep_blocks"},
    $hdfs{"under_rep_blocks_pc"},
    $hdfs{"mis_rep_blocks"},
    $hdfs{"mis_rep_blocks_pc"},
    $hdfs{"default_rep_factor"},
    $hdfs{"avg_block_rep"},
    $hdfs{"corrupt_blocks"},
    $hdfs{"missing_replicas"},
    $hdfs{"missing_replicas_pc"},
    $hdfs{"num_datanodes"},
    $hdfs{"num_racks"}
    );
    my $msg3 = $msg2;
    $msg3 =~ s/'//g;
    $msg3 =~ s/\s+\w+_%=([^\s]+)/($1)/g;
    #$msg3 =~ s/_/ /g;
    $msg .= $msg3;
}
$msg .= " |";
$msg .= " last_fsck=$hdfs{fsck_age}s";
msg_perf_thresholds() if $last_fsck;
$msg .= " fsck_time=$hdfs{fsck_time}s";
msg_perf_thresholds() if $fsck_time;
$msg .= " total_blocks=$hdfs{blocks}";
msg_perf_thresholds() if $max_blocks;
$msg .= $msg2 if defined($msg2);

quit $status, $msg;
