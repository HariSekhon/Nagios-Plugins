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

$DESCRIPTION = "Nagios Plugin to parse and alert on Hadoop FSCK output

Checks the status of the HDFS FSCK output and optionally the HDFS block count against warning/critical thresholds

In order to contrain the runtime of this plugin you must run the Hadoop FSCK separately and have this plugin check the output file results

hdfs fsck / &> /tmp/hdfs-fsck.log.tmp && mv /tmp/hdfs-fsck.log

./check_hadoop_fsck.pl -f /tmp/hdfs-fsck.log

Tested on Hortonworks HDP 2.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

my $file;

%options = (
    "f|file=s"      => [ \$file,         "HDFS FSCK result file" ],
    "w|warning=s"   => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"  => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/file total-blocks warning critical/;
get_options();
$file or usage "hdfs fsck result file not specified";
$file = validate_file($file);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

vlog2;
set_timeout();

$status = "OK";

my $fh = open_file $file;
my %hdfs;
while(<$fh>){
    chomp;
    vlog3 "output: $_";
    /Permission denied/i and quit "CRITICAL", "Did you fail to run this as the hdfs superuser? $_";
    if(/^\//){
        next;
    } elsif(/Status:\s*(\w+)/){
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
    } elsif(/^\s*Number of data-nodes:\s*(\d+)/){
        $hdfs{"num_datanodes"} = $1;
    } elsif(/^\s*Number of racks:\s*(\d+)/){
        $hdfs{"num_racks"} = $1;
    } elsif(/^FSCK ended at (\w+\s+\w+\s+\d+\s+\d{1,2}:\d{2}:\d{2} \w+ \d+) in (\d+) milliseconds/){
        $hdfs{"fsck_ended"} = $1;
        $hdfs{"duration"}   = $2;
    }
    /error/i and quit "CRITICAL", "error detected: $_";
#    quit "UNKNOWN", "unknown line detected: '$_'. $nagios_plugins_support_msg";
}

foreach(qw/status size dirs files blocks min_rep_blocks min_rep_blocks_pc over_rep_blocks over_rep_blocks_pc under_rep_blocks under_rep_blocks_pc mis_rep_blocks mis_rep_blocks_pc default_rep_factor avg_block_rep corrupt_blocks missing_replicas missing_replicas_pc num_datanodes num_racks fsck_ended duration/){
    unless(defined($hdfs{$_})){
        quit "UNKNOWN", "hdfs $_ not found. $nagios_plugins_support_msg";
    }
}
critical unless $hdfs{"status"} eq "HEALTHY";

if($hdfs{"blocks"} == 0){
    quit "UNKNOWN", "zero total blocks detected, unless this is a brand new cluster, $nagios_plugins_support_msg";
}
#vlog2 "blocks: $hdfs{blocks}";

$msg = "hdfs status: $hdfs{status}";
$msg .= sprintf(", last checked %s in %d secs", $hdfs{fsck_ended}, $hdfs{duration} / 1000);
if($verbose or $warning or $critical){
    $msg .= ", blocks=$hdfs{blocks}";
    check_thresholds($hdfs{"blocks"});
}
if($verbose){
    my $msg2 = sprintf(" size=%s dirs=%d files=%d min_replicated_blocks=%d 'min_replicated_blocks_%%'=%.2f%% over_rep_blocks=%d 'over_rep_blocks_%%'=%.2f%% under_rep_blocks=%d 'under_rep_blocks_%%'=%.2f%% mis_rep_blocks=%d 'mis_rep_blocks_%%'=%.2f%% default_rep_factor=%d avg_block_rep=%.2f corrupt_blocks=%d missing_replicas=%d 'missing_replicas_%%'=%.2f%% num_datanodes=%d num_racks=%d",
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
    $msg3 =~ s/_/ /g;
    $msg .= $msg3;
    
    $msg .= " | hdfs_blocks=$hdfs{blocks}";
    msg_perf_thresholds();
    $msg .= $msg2;
}

quit $status, $msg;
