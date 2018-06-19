#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-08-24 12:20:34 +0100 (Fri, 24 Aug 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# XXX: switch to % of corrupt / under-replicated blocks like Cloudera Manager 90c 95 warning

# TODO: node list checks
# TODO: list dead datanodes

$DESCRIPTION = "Nagios Hadoop Plugin to check various health aspects of HDFS via the Namenode's dfsadmin -report

- checks % HDFS space used. Based off an earlier plugin I wrote in 2010 that we used in production for over 2 years. This heavily leverages HariSekhonUtils so code in this file is very short but still much tighter validated
- checks HDFS replication of blocks, again based off another plugin I wrote in 2010 around the same time as above and ran in production for 2 years. This code unifies/dedupes and improves on both those plugins
- checks HDFS % Used Balance is within thresholds
- checks number of available datanodes and if there are any dead datanodes

Originally written for old vanilla Apache Hadoop 0.20.x, updated and tested on:

CDH 4.3 (Hadoop 2.0.0)
CDH 5.0 (Hadoop 2.3.0)
HDP 2.1 (Hadoop 2.4.0)
HDP 2.2 (Hadoop 2.6.0)
Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9

See also check_hadoop_jmx.pl which can report Missing and Corrupt blocks, but be aware that the calculation mechanism between JMX and dfsadmin differ, see this ticket:

    https://issues.apache.org/jira/browse/HDFS-8533

Recommend you also investigate check_hadoop_cloudera_manager_metrics.pl (disclaimer I used to work for Cloudera but seriously it's good it gives you access to a wealth of information)";

# TODO:
# Features to add: (these are my old colleague Rob Dawson's idea from his check_hadoop_node_status.pl plugin)
# 1. Min Configured Capacity per node (from node section output).
# 2. Last Contact: convert the date to secs and check against thresholds.

$VERSION = "0.9.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$ENV{"PATH"} .= ":/opt/hadoop/bin:/usr/local/hadoop/bin";

my $default_hadoop_user = "hdfs";
my $default_hadoop_bin  = "hdfs";
my $legacy_hadoop_user  = "hadoop";
my $legacy_hadoop_bin   = "hadoop";

my $hadoop_bin  = $default_hadoop_bin;
my $hadoop_user = $default_hadoop_user;

my $hdfs_space  = 0;
my $replication = 0;
my $balance     = 0;
my $nodes       = 0;

%options = (
    "s|hdfs-space"      => [ \$hdfs_space,   "Checks % HDFS Space used against given warning/critical thresholds" ],
    "r|replication"     => [ \$replication,  "Checks replication state: under replicated blocks, corrupt blocks, missing blocks. Warning/critical thresholds apply to under replicated blocks. Corrupt and missing blocks if any raise critical since this means there is potentially data loss" ],
    "b|balance"         => [ \$balance,      "Checks Balance of HDFS Space used % across datanodes is within thresholds. Lists the nodes out of balance in verbose mode" ],
    "n|nodes-available" => [ \$nodes,        "Checks the number of available datanodes against the given warning/critical thresholds as the lower limits (inclusive). Any dead datanodes raises warning" ],
    %thresholdoptions,
    "hadoop-bin=s"      => [ \$hadoop_bin,   "Path to 'hdfs' or 'hadoop' command if not in \$PATH" ],
    "hadoop-user=s"     => [ \$hadoop_user,  "Checks that this plugin is being run by the hadoop user (defaults to '$default_hadoop_user', falls back to trying '$legacy_hadoop_user' unless specified)" ],
);

@usage_order = qw/hdfs-space replication balance nodes-available warning critical hadoop-bin hadoop-user/;
get_options();

if($progname eq "check_hadoop_hdfs_space.pl"){
    vlog2 "checking HDFS % space used";
    $hdfs_space = 1;
} elsif($progname eq "check_hadoop_replication.pl"){
    vlog2 "checking HDFS replication";
    $replication = 1;
} elsif($progname eq "check_hadoop_balance.pl"){
    vlog2 "checking HDFS balance";
    $balance = 1;
} elsif($progname eq "check_hadoop_datanodes.pl"){
    vlog2 "checking HDFS datanodes available";
    $nodes = 1;
}
unless($hdfs_space or $replication or $balance or $nodes){
    usage "must specify one of --hdfs-space / --replication / --balance / --nodes-available to check";
}
if($hdfs_space + $replication + $balance + $nodes > 1){
    usage "can only check one of HDFS space used %, replication, HDFS balance, datanodes available at one time, otherwise the warning/critical thresholds will conflict or require a large number of switches";
}
if($replication){
    validate_thresholds(1, 1, {
                            "positive" => 1,
                            "integer"  => 1
                            });
} elsif($hdfs_space or $replication or $balance){
    validate_thresholds(1, 1, {
                            "positive" => 1,
                            "max"      => 100
                            });
} elsif($nodes){
    validate_thresholds(1, 1, {
                            "simple"   => "lower",
                            "positive" => 1,
                            "integer"  => 1
                            });
}

$hadoop_user = validate_user($hadoop_user);
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
vlog_option "hadoop path", $hadoop_bin;
vlog2;
set_timeout();

my $cmd;
if(!user_exists($hadoop_user)){
    if($hadoop_user eq $default_hadoop_user and user_exists($legacy_hadoop_user)){
        vlog2 "user '$default_hadoop_user' does not exist, but found user '$legacy_hadoop_user', trying that instead for compatability";
        $hadoop_user = $legacy_hadoop_user;
    } else {
        usage "user '$hadoop_user' does not exist, specify different --hadoop-user?"
    }
}
unless(getpwuid($>) eq $hadoop_user){
    # Quit if we're not the right user to ensure we don't sudo command and hang or return with a generic timeout error message
    #quit "UNKNOWN", "not running as '$hadoop_user' user";
    # only Mac has -n switch for non-interactive :-/
    #$cmd = "sudo -n -u $hadoop_user ";
    vlog2 "effective user ID is not $hadoop_user, using sudo";
    $cmd = "echo | sudo -S -u $hadoop_user ";
}

vlog2 "fetching HDFS report";
$cmd .= "$hadoop_bin dfsadmin -report 2>&1";
my @output = cmd($cmd, 1); # quit with error if non zero exit code
my %dfs;
vlog2 "parsing HDFS report";
my %datanodes;
if(join("", @output) =~ /^\s*$/){
    quit "CRITICAL", "blank output returned from '$cmd' (wrong user or mis-configured HDFS cluster settings?)";
}
$dfs{"missing_blocks"} = 0;
foreach(@output){
    # skip blank lines and lines with just --------------------
    if (/^(?:-+|\s*)$/ or /DEPRECATED|Instead use the hdfs command for it|Live datanodes:/){
        next;
    } elsif(/Safe mode is ON/){
        next;
    } elsif (/^Configured Capacity:\s*(\d+)\s+\((.+)\)\s*$/i){
        $dfs{"configured_capacity"}       = $1;
        $dfs{"configured_capacity_human"} = $2;
    } elsif (/^Present Capacity:\s*(\d+)\s+\((.+)\)\s*$/i){
        $dfs{"present_capacity"}          = $1;
        $dfs{"present_capacity_human"}    = $2;
    } elsif (/^DFS Remaining:\s*(\d+)\s+\((.+)\)\s*$/i){
        $dfs{"dfs_remaining"}       = $1;
        $dfs{"dfs_remaining_human"} = $2;
    } elsif(/^DFS Used:\s*(\d+)\s+\((.+)\)\s*$/i){
        $dfs{"dfs_used"}        = $1;
        $dfs{"dfs_used_human"}  = $2;
    } elsif(/^DFS Used\%:\s*(\d+(?:\.\d+)?|NaN)\%\s*$/i){
        $dfs{"dfs_used_pc"} = $1;
    } elsif(/^Under replicated blocks:\s*(\d+)\s*$/i){
        $dfs{"under_replicated_blocks"} = $1;
    } elsif(/^Blocks with corrupt replicas:\s*(\d+)\s*$/i){
        $dfs{"corrupt_blocks"} = $1;
    } elsif(/^Missing blocks:\s*(\d+)\s*$/i){
        $dfs{"missing_blocks"} += $1;
    } elsif(/^Missing blocks\s*\(with replication factor\s\d+\):\s*(\d+)\s*$/i){
        # This might not be accurate to accumulate but safer than ignoring it, at worst it'll lead to a higher missing block count we can correct later rather than missing this scenario entirely the number isn't included in the base missing blocks
        $dfs{"missing_blocks"} += $1;
    } elsif(/^Datanodes available:\s*(\d+)\s*(?:\((\d+) total, (\d+) dead\))?\s*$/i){
        $dfs{"datanodes_available"} = $1;
        $dfs{"datanodes_total"}     = $2 if defined($2);
        $dfs{"datanodes_dead"}      = $3 if defined($3);
    } elsif(/Live\sdatanodes\s+\((\d+)\)/){
        $dfs{"datanodes_available"} = $1;
    } elsif(/Dead\s+datanodes\s+\((\d+)\)/){
        $dfs{"datanodes_dead"} = $1;
        last;
    } elsif(/^Name:/){
        last;
    #} else {
    #    quit "UNKNOWN", "Unrecognized line in output while parsing totals: '$_'. $nagios_plugins_support_msg_api";
    }
}
if($balance){
    my $i = 0;
    foreach(@output){
        $i++;
        if(/^(?:Datanodes available|Live datanodes)\b.*:/i){
            last;
        }
        next;
    }
    my $name;
    my $no_name_err = "parsing failed to determine name of node before finding DFS Used% in output from dfs -report";
    foreach(; $i< scalar @output; $i++){
        $_ = $output[$i];
        if(/^\s*$/){
            $name = "";
        } elsif(/^Name:\s*(.+?)\s*$/){
            $name = $1;
        } elsif(/^Hostname:/){
            next;
        } elsif(/^Configured Capacity: 0 \(0 KB\)$/){
            $name or code_error $no_name_err;
            $datanodes{$name}{"dead"} = 1;
        } elsif(/^DFS Used%:\s*(\d+(?:\.\d+)?)%$/){
            $name or code_error $no_name_err;
            $datanodes{$name}{"used_pc"} = $1;
        # Ignore these lines for now
        # TODO: could add exception for Decommissioning Nodes to not be considered part of the cluster balance
        } elsif(/^(?:Rack|Decommission Status|Configured Capacity|DFS Used|Non DFS Used|DFS Remaining|DFS Remaining%|Configured Cache Capacity|Cache Used|Cache Remaining|Cache Used%|Cache Remaining%|Last contact|Xceivers|)\s*:|^\s*$/){
            next;
        } elsif(/Live datanodes(?: \(\d+\))?:/){
            next;
        } elsif(/Dead datanodes(?: \(\d+\))?:/){
            last;
        } elsif(/Last Block Report: /){
            next;
        } else {
            quit "UNKNOWN", "Unrecognized line in output while parsing nodes: '$_'. $nagios_plugins_support_msg_api";
        }
    }
    foreach(keys %datanodes){
        delete $datanodes{$_} if $datanodes{$_}{"dead"};
    }
}

sub check_parsed {
    foreach(@_){
        unless(defined($dfs{$_})){
            quit "UNKNOWN", "Failed to determine $_. $nagios_plugins_support_msg";
        }
        vlog2 "$_: $dfs{$_}";
    }
}

vlog2;
check_parsed(qw/
        configured_capacity
        configured_capacity_human
        present_capacity
        present_capacity_human
        dfs_remaining
        dfs_remaining_human
        dfs_used
        dfs_used_human
        dfs_used_pc
        under_replicated_blocks
        corrupt_blocks
        missing_blocks
        /);
        #datanodes_available
        #datanodes_total
        #datanodes_dead
#############
unless(defined($dfs{"datanodes_available"})){
    # safety check
    grep(/\bavailable\b/i, @output) and quit "CRITICAL", "'available' word detected in output but available datanode count was not parsed. $nagios_plugins_support_msg";
    $dfs{"datanodes_available"} = 0;
}
# Apache 2.6.0 no longer outputs datanodes total or datanodes dead - must assume 0 dead datanodes if we can't find dead in output
unless(defined($dfs{"datanodes_dead"})){
    # safety check
    grep(/\bdead\b/i, @output) and quit "CRITICAL", "'dead' word detected in output but dead datanode count was not parsed. $nagios_plugins_support_msg";
    # must be Apache 2.6+ with no dead datanodes
    $dfs{"datanodes_dead"} = 0;
}
unless(defined($dfs{"datanodes_total"})){
    $dfs{"datanodes_total"} = $dfs{"datanodes_available"} + $dfs{"datanodes_dead"};;
}
#############
vlog2;

$status = "UNKNOWN";
$msg    = "NO TESTS DONE!!! Please choose something to test";

if($hdfs_space){
    $status = "OK"; # ok unless check_thresholds says otherwise
    # happens when there are no datanodes online
    if($dfs{"dfs_used_pc"} eq "NaN"){
        unknown();
        $msg = sprintf("N/A%% HDFS space used");
        # reset for graphing in case it breaks on non-numeric
        $dfs{"dfs_used_pc"} = 0;
    } else {
        $msg = sprintf("%.2f%% HDFS space used", $dfs{"dfs_used_pc"});
        check_thresholds($dfs{"dfs_used_pc"});
    }
    plural $dfs{"datanodes_available"};
    $msg .= sprintf(" on %d available datanode$plural", $dfs{"datanodes_available"});
    if($dfs{"datanodes_available"} < 1){
        warning();
        $msg .= " (< 1)";
    }
    $msg .= " | 'HDFS Space Used'=$dfs{dfs_used_pc}%;$thresholds{warning}{upper};$thresholds{critical}{upper} 'HDFS Used Capacity'=$dfs{dfs_used}B;;0;$dfs{configured_capacity} 'HDFS Present Capacity'=$dfs{present_capacity}B 'HDFS Configured Capacity'=$dfs{configured_capacity}B 'Datanodes Available'=$dfs{datanodes_available}";
} elsif($replication){
    $status = "OK";
    $msg = sprintf("under replicated blocks: %d, corrupt blocks: %d, missing blocks: %d", $dfs{"under_replicated_blocks"}, $dfs{"corrupt_blocks"}, $dfs{"missing_blocks"});
    check_thresholds($dfs{"under_replicated_blocks"});
    if($dfs{"corrupt_blocks"} or $dfs{"missing_blocks"}){
        critical;
        $msg = "corrupt/missing blocks detected. $msg";
    }
    $msg .= " | 'under replicated blocks'=$dfs{under_replicated_blocks};$thresholds{warning}{upper};$thresholds{critical}{upper} 'corrupt blocks'=$dfs{corrupt_blocks} 'missing blocks'=$dfs{missing_blocks}";
} elsif($balance){
    foreach(sort keys %datanodes){
        vlog2 sprintf("datanode '%s' used pc: %.2f%%", $_, $datanodes{$_}{"used_pc"});
    }
    vlog2;
    if(scalar keys %datanodes ne $dfs{"datanodes_available"}){
        quit "UNKNOWN", sprintf("Mismatch on collected number of datanode used %% (%d) and number of available datanodes (%d)", scalar keys %datanodes, $dfs{"datanodes_available"});
    }
    my %datanodes_imbalance;
    #@datanodes = sort @datanodes;
    # Trying to use the same algorithm as is used by hadoop balancer -threshold command which I believe diffs the cluster used % against a datanode's used %
    #my $max_datanode_used_pc_diff = abs($dfs{"dfs_used_pc"} - $datanodes[-1]);
    #my $min_datanode_used_pc_diff = abs($dfs{"dfs_used_pc"} - $datanodes[0]);
    #my $largest_datanode_used_pc_diff = $max_datanode_used_pc_diff > $min_datanode_used_pc_diff ? $max_datanode_used_pc_diff : $min_datanode_used_pc_diff;
    # switching to allow collection of datanodes which are out of balance
    my $largest_datanode_used_pc_diff = -1;
    my $num_datanodes = scalar keys %datanodes;
    if($num_datanodes < 1){
        $largest_datanode_used_pc_diff = 0;
    }
    foreach(keys %datanodes){
        $datanodes_imbalance{$_} = abs($dfs{"dfs_used_pc"} - $datanodes{$_}{"used_pc"});
        $largest_datanode_used_pc_diff = $datanodes_imbalance{$_} if($datanodes_imbalance{$_} > $largest_datanode_used_pc_diff);
    }
    ( $largest_datanode_used_pc_diff >= 0 ) or code_error "largest_datanode_used_pc_diff is '$largest_datanode_used_pc_diff', cannot be less than 0, this is not possible";
    $largest_datanode_used_pc_diff = sprintf("%.2f", $largest_datanode_used_pc_diff);
    $status = "OK";
    $msg = sprintf("%.2f%% HDFS imbalance on space used %%", $largest_datanode_used_pc_diff);
    check_thresholds($largest_datanode_used_pc_diff);
    plural $num_datanodes;
    $msg .= sprintf(" across %d datanode$plural", $num_datanodes);
    if($num_datanodes < 1){
        warning();
        $msg .= " (< 1)";
    }
    if($verbose and
       $num_datanodes > 0 and
       (is_warning or is_critical)){
        my $msg2 = " [imbalanced nodes: ";
        foreach(sort keys %datanodes_imbalance){
            if($datanodes_imbalance{$_} >= $thresholds{"warning"}{"upper"}){
                $msg2 .= sprintf("%s(%.2f%%),", $_, $datanodes_imbalance{$_});
            }
        }
        $msg2 =~ s/,$/]/;
        $msg .= $msg2;
    }
    $msg .= " | 'HDFS imbalance on space used %'=$largest_datanode_used_pc_diff%;$thresholds{warning}{upper};$thresholds{critical}{upper}";
} elsif($nodes){
    $status = "OK";
    plural $dfs{"datanodes_available"};
    $msg = sprintf("%d datanode$plural available, %d dead, %d total", $dfs{"datanodes_available"}, $dfs{"datanodes_dead"}, $dfs{"datanodes_total"});
    check_thresholds($dfs{"datanodes_available"});
    warning if $dfs{"datanodes_dead"};
    $msg .= " | 'Datanodes Available'=$dfs{datanodes_available};$thresholds{warning}{lower};$thresholds{critical}{lower} 'Datanodes Dead'=$dfs{datanodes_dead} 'Datanodes Total'=$dfs{datanodes_total}";
} else {
    quit "UNKNOWN", "no test section specified";
}

quit $status, $msg;
