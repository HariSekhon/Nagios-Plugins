#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-08-24 12:20:34 +0100 (Fri, 24 Aug 2012)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to run various checks against the Hadoop HDFS Cluster via the Namenode JSP pages

This is an alternate rewrite of the functionality from my previous check_hadoop_dfs.pl plugin
using the Namenode JSP interface instead of the hadoop dfsadmin -report output

Recommend to use the original check_hadoop_dfs.pl plugin it's better tested and has better/tighter output validation than this one, but this one is useful for the following reasons:
1. you can check your NameNode remotely via JSP without having to adjust the NameNode setup to install the check_hadoop_dfs.pl plugin
2. it can check Namenode Heap Usage

Caveats:
1. Cannot currently detect corrupt or under-replicated blocks since JSP doesn't offer this information
2. There are no byte counters, so we can only use the human summary and multiply out, and being a multiplier of a summary figure it's marginally less accurate

Note: This was created for Apache Hadoop 0.20.2, r911707 and updated for CDH 4.3 (2.0.0-cdh4.3.0). If JSP output changes across versions, this plugin will need to be updated to parse the changes";

$VERSION = "0.2";

use strict;
use warnings;
use LWP::Simple qw/get $ua/;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $balance         = 0;
#my $dead_nodes      = 0;
my $hdfs_space      = 0;
my $heap            = 0;
my $node_list        = "";
my $node_count      = 0;
my $replication     = 0;

# this is really just for contraining the size of the output printed
my $MAX_NODES_TO_DISPLAY_AS_ACTIVE  = 5;
my $MAX_NODES_TO_DISPLAY_AS_MISSING = 30;

my %stats;
my %dfs;
my $namenode_urn             = "dfshealth.jsp";
my $namenode_urn_live_nodes  = "dfsnodelist.jsp?whatNodes=LIVE";
my $namenode_urn_dead_nodes  = "dfsnodelist.jsp?whatNodes=DEAD";
my $default_port             = "50070";
$port                        = $default_port;

%options = (
    "H|host=s"          => [ \$host,            "Namenode to connect to" ],
    "P|port=s"          => [ \$port,            "Namenode port to connect to (defaults to $default_port)" ],
    "s|hdfs-space"      => [ \$hdfs_space,      "Checks % HDFS Space used against given warning/critical thresholds" ],
    "r|replication"     => [ \$replication,     "Checks replication state: under replicated blocks, blocks with corrupt replicas, missing blocks. Warning/critical thresholds apply to under replicated blocks. Corrupt replicas and missing blocks if any raise critical since this can result in data loss" ],
    "b|balance"         => [ \$balance,         "Checks Balance of HDFS Space used % across datanodes is within thresholds. Lists the nodes out of balance in verbose mode" ],
    "m|node-count"      => [ \$node_count,      "Checks the number of available datanodes against the given warning/critical thresholds as the lower limits (inclusive). Any dead datanodes raises warning" ],
    "n|node-list=s"     => [ \$node_list,       "List of datanodes to expect are available on namenode (non-switch args are appended to this list for convenience). Warning/Critical thresholds default to zero if not specified" ],
    # TODO:
    #"d|dead-nodes"      => [ \$dead_nodes,      "List all dead datanodes" ],
    "heap-usage"        => [ \$heap,            "Check Namenode Heap % Used. Optional % thresholds may be supplied for warning and/or critical" ],
    "w|warning=s"       => [ \$warning,         "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"      => [ \$critical,        "Critical threshold or ran:ge (inclusive)" ],
);
@usage_order = qw/host port hdfs-space replication balance node-count node-list heap-usage warning critical/;

get_options();

defined($host)  or usage "Namenode host not specified";
$host = isHost($host) || usage "Namenode host invalid, must be hostname/FQDN or IP address";
vlog_options "host", "'$host'";
$port = validate_port($port);
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
    vlog2 "checking HDFS datanodes number available";
    $node_count = 1;
} elsif($progname eq "check_hadoop_datanode_list.pl"){
    vlog "checking HDFS datanode list";
#} elsif($progname eq "check_hadoop_dead_datanodes.pl"){
#    vlog "checking HDFS dead datanode list";
}

my $url;
my @nodes;

if($node_list){
    @nodes = split(/\s*,\s*/, $node_list);
    push(@nodes, @ARGV); # for convenience as mentioned in usage
    vlog_options "nodes", "[ " . join(", ", @nodes) . " ]";
    @nodes or usage "must specify nodes if using -n / --node-list switch";
}
unless($hdfs_space or $replication or $balance or $node_count or $node_list or $heap){
    usage "must specify one of --hdfs-space / --replication / --balance / --node-count / --node-list / --heap-usage to check";
}
if($hdfs_space + $replication + $balance + $node_count + ($node_list?1:0) + $heap > 1){
    usage "can only check one of --hdfs-space / --replication / --balance / --node-count / --node-list / --heap-usage at one time in order to make sense of thresholds";
}
if($hdfs_space or $balance or $heap){
    validate_thresholds(1, 1, {
                            "simple"   => "upper",
                            "integer"  => 0,
                            "positive" => 1,
                            "max"      => 100
                            });
} elsif($node_count){
    validate_thresholds(1, 1, {
                            "simple"   => "lower",
                            "integer"  => 1,
                            "positive" => 1
                            });
} elsif($node_list){
    $warning  = 0 unless $warning;
    $critical = 0 unless $critical;
    validate_thresholds(1, 1, {
                            "simple"   => "upper",
                            "integer"  => 1,
                            "positive" => 1
                            });
} else {
    validate_thresholds(1, 1);
}

$url = "http://$host:$port/$namenode_urn";
my $url_live_nodes = "http://$host:$port/$namenode_urn_live_nodes";
my $url_dead_nodes = "http://$host:$port/$namenode_urn_dead_nodes";

vlog2;
set_timeout();
#$ua->timeout($timeout);

validate_resolvable($host);
my $content = curl $url;

my $regex_td = '\s*(?:<\/a>\s*)?<td\s+id="\w+">\s*:\s*<td\s+id="\w+">\s*';

sub parse_dfshealth {
    # Note: This was created for Apache Hadoop 0.20.2, r911707. If they change this page across versions, this plugin will need to be updated to parse the changes
    vlog2 "parsing Namenode dfs health output";

    my $regex_configured_capacity = qr/>\s*Configured Capacity$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    my $regex_dfs_used            = qr/>\s*DFS Used$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    my $regex_dfs_used_pc         = qr/>\s*DFS Used%\s*<td\s+id="\w+">\s*:\s*<td\s+id="\w+">\s*(\d+(?:\.\d+)?)\s*%\s*</o;
    my $regex_live_nodes          = qr/>\s*Live Nodes$regex_td(\d+)\s*/o;
    my $regex_dead_nodes          = qr/>\s*Dead Nodes$regex_td(\d+)\s*/o;
#    my $regex_present_capacity    = qr/>\s*Present Capacity$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    if($content =~ /$regex_live_nodes/o){
        $dfs{"datanodes_available"} = $1;
    }
    if($content =~ /$regex_dead_nodes/o){
        $dfs{"datanodes_dead"} = $1;
    }
    # These multiplier calculations are slightly less accurate than the actual amount given by the hadoop dfsadmin -report that my other plugin uses but since the web page doesn't give the bytes count I have to estimate it by plain multiplier (JSP pages are only giving the rounded summary that I am then having to multiply
    if($content =~ /$regex_dfs_used/o){
        $dfs{"dfs_used_human"} = $1;
        $dfs{"dfs_used_units"} = $2;
        $dfs{"dfs_used"} = expand_units($1, $2, "DFS Used");
    }
    if($content =~ /$regex_dfs_used_pc/o){
        $dfs{"dfs_used_pc"} = $1;
    }
    if($content =~ /$regex_configured_capacity/o){
        $dfs{"configured_capacity_human"} = $1;
        $dfs{"configured_capacity_units"} = $2;
        $dfs{"configured_capacity"} = expand_units($1, $2, "Configured Capacity");
    }
#    print "Present Capacity: $regex_present_capacity\n";
#    if($content =~ /$regex_present_capacity/o){
#        $dfs{"present_capacity_human"} = $1;
#        $dfs{"present_capacity"} = expand_units($1, $2, "Present Capacity");
#    }

    vlog2;
    check_parsed(qw/
            configured_capacity
            configured_capacity_human
            configured_capacity_units
            dfs_used
            dfs_used_human
            dfs_used_units
            dfs_used_pc
            datanodes_available
            datanodes_dead
            /);
    vlog2;
}


sub check_parsed {
    foreach(@_){
        unless(defined($dfs{$_})){
            quit "UNKNOWN", "Failed to determine $_, either output is incomplete or format has changed, use -vvv to debug";
        }
        vlog2 "$_: $dfs{$_}";
    }
}


#############
if($balance){
    parse_dfshealth();
    $content = curl $url_live_nodes;
    vlog2 "parsing Namenode datanode % usage\n";
    if($content =~ />\s*Live Datanodes\s*:*\s*(\d+)\s*</){
        $dfs{"datanodes_available"} = $1;
    } else {
        quit "UNKNOWN", "couldn't find Live Datanodes in output from $url";
    }
    my %datanodes_used_pc;
    my $regex_datanode_used_pc = qr/<td\s+class="name"><a[^>]+>\s*($hostname_regex|$ip_regex)\s*<\/a>.+<td\s+align="right"\s+class="pcused">\s*(\d+(?:\.\d+)?)\s*</o;
    foreach(split(/\n/, $content)){
        if(/$regex_datanode_used_pc/){
            $datanodes_used_pc{$1} = $2;
        }
    }
    foreach(sort keys %datanodes_used_pc){
        vlog2 sprintf("datanode '%s' used pc: %.2f%%", $_, $datanodes_used_pc{$_});
    }
    vlog2;
    if(scalar keys %datanodes_used_pc ne $dfs{"datanodes_available"}){
        quit "UNKNOWN", sprintf("Mismatch on collected number of datanode used %% (%d) and number of available datanodes (%d)", scalar keys %datanodes_used_pc, $dfs{"datanodes_available"});
    }
    my %datanodes_imbalance;
    my $largest_datanode_used_pc_diff = -1;
    foreach(keys %datanodes_used_pc){
        $datanodes_imbalance{$_} = abs($dfs{"dfs_used_pc"} - $datanodes_used_pc{$_});
        $largest_datanode_used_pc_diff = $datanodes_imbalance{$_} if($datanodes_imbalance{$_} > $largest_datanode_used_pc_diff);
    }
    ( $largest_datanode_used_pc_diff >= 0 ) or code_error "largest_datanode_used_pc_diff is less than 0, this is not possible";
    $largest_datanode_used_pc_diff = sprintf("%.2f", $largest_datanode_used_pc_diff);
    $status = "OK";
    $msg = sprintf("%.2f%% HDFS imbalance on space used %% across %d datanodes", $largest_datanode_used_pc_diff, scalar keys %datanodes_used_pc);
    check_thresholds($largest_datanode_used_pc_diff);
    if(is_warning or is_critical){
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

#####################
} elsif($hdfs_space){
    parse_dfshealth();
    $status = "OK"; # ok unless check_thresholds says otherwise
    $msg = sprintf("%.2f%% HDFS space used ($dfs{dfs_used_human}$dfs{dfs_used_units}/$dfs{configured_capacity_human}$dfs{configured_capacity_units}) on %d available datanodes", $dfs{"dfs_used_pc"}, $dfs{"datanodes_available"});
    check_thresholds($dfs{"dfs_used_pc"});
    # JSP Pages don't give Present Capacity
    #$msg .= " | 'HDFS Space Used'=$dfs{dfs_used_pc}%;$thresholds{warning}{upper};$thresholds{critical}{upper} 'HDFS Used Capacity'=$dfs{dfs_used}B;;0;$dfs{configured_capacity} 'HDFS Present Capacity'=$dfs{present_capacity}B 'HDFS Configured Capacity'=$dfs{configured_capacity}B 'Datanodes Available'=$dfs{datanodes_available}";
    $msg .= " | 'HDFS Space Used'=$dfs{dfs_used_pc}%;$thresholds{warning}{upper};$thresholds{critical}{upper} 'HDFS Used Capacity'=$dfs{dfs_used}B;;0;$dfs{configured_capacity} 'HDFS Configured Capacity'=$dfs{configured_capacity}B 'Datanodes Available'=$dfs{datanodes_available}";

######################
} elsif($replication){
    if($content =~ /(\d+) corrupt blocks/i or $content =~ />\s*Number of Corrupt Blocks\b$regex_td\s*(\d+)/i){
        $dfs{"corrupt_blocks"} = $1;
    }
    if($content =~ /(\d+) missing blocks/i or $content =~ />\s*Number of Missing Blocks\b$regex_td\s*(\d+)/i){
        $dfs{"missing_blocks"} = $1;
    }
    if($content =~ /(\d+) under-replicated blocks/i or $content =~ />\s*Number of Under-Replicated Blocks\b$regex_td\s*(\d+)/i){
        $dfs{"under_replicated_blocks"} = $1;
    }
    if(not (defined($dfs{"corrupt_blocks"}) or defined($dfs{"missing_blocks"})) ){
        if($content =~ /fsck/i){
            warning;
            $msg = "FSCK mentioned on Namenode page '$url' but no missing or corrupt blocks were detected, code possibly needs updating?";
        } elsif($content =~ /warning/i){
            warning;
            $msg = "'Warning' mentioned on Namenode page '$url' but no missing or corrupt blocks were detected, code possibly needs updating?";
        }
    }
    unless(defined($dfs{"corrupt_blocks"})){
        vlog2 "corrupt blocks not found on Namenode page, assuming 0";
        $dfs{"corrupt_blocks"} = 0;
    }
    unless(defined($dfs{"missing_blocks"})){
        vlog2 "missing blocks not found on Namenode page, assuming 0";
        $dfs{"missing_blocks"} = 0;
    }
    unless(defined($dfs{"under_replicated_blocks"})){
        vlog2 "under replicated blocks not found on Namenode page, assuming 0";
        $dfs{"under_replicated_blocks"} = 0;
    }
    $status = "OK";
    #$msg = sprintf("under replicated blocks: %d, corrupt blocks: %d, missing blocks: %d", $dfs{"under_replicated_blocks"}, $dfs{"corrupt_blocks"}, $dfs{"missing_blocks"});
    check_thresholds($dfs{"under_replicated_blocks"});
    $msg = sprintf("under replicated blocks: %d, corrupt blocks: %d, missing blocks: %d", $dfs{"under_replicated_blocks"}, $dfs{"corrupt_blocks"}, $dfs{"missing_blocks"});
    if($dfs{"corrupt_blocks"} or $dfs{"missing_blocks"}){
        critical;
        $msg = "corrupt/missing blocks detected. $msg";
    }
    $msg .= " | 'under replicated blocks'=$dfs{under_replicated_blocks};$thresholds{warning}{upper};$thresholds{critical}{upper} 'corrupt blocks'=$dfs{corrupt_blocks} 'missing blocks'=$dfs{missing_blocks}";

################
} elsif($node_count){
    $status = "OK";
    parse_dfshealth();
    $msg = "";
    if($dfs{"datanodes_dead"}){
        warning;
        $msg .= sprintf("%d dead datanodes, ", $dfs{"datanodes_dead"});
    }
    $msg .= sprintf("%d datanodes available", $dfs{"datanodes_available"});
    check_thresholds($dfs{"datanodes_available"});
    $msg .= sprintf(" | datanodes_available=%d datanodes_dead=%d", $dfs{"datanodes_available"}, $dfs{"datanodes_dead"});
################
} elsif($node_list){
    my @missing_nodes;
    $content = curl $url_live_nodes;
    foreach my $node (@nodes){
        unless($content =~ />$node(?:\.$domain_regex)?<\//m){
            push(@missing_nodes, $node);
        }
    }

    $node_count = scalar @nodes;
    plural($node_count);
    my $missing_nodes = scalar @missing_nodes;
    $status = "OK";
    if(@missing_nodes){
        if($missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg = "'" . join(",", sort @missing_nodes) . "'";
        } else {
            $msg = "$missing_nodes/$node_count node$plural";
        }
        $msg .= " not";
    } else {
        if($node_count <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg = "'" . join(",", sort @nodes) . "'";
        } else {
            $msg = "$node_count/$node_count checked node$plural";
        }
    }
    $msg .= " found in the active nodes list on the Namenode" . ($verbose ? " at '$host:$port'" : "");
    if($verbose){
        if($missing_nodes and $missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg .= " ($missing_nodes/$node_count checked node$plural)";
        } elsif ($node_count <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg .= " ($node_count/$node_count checked node$plural)";
        }
    }
    check_thresholds(scalar @missing_nodes);
################
#} elsif($dead_nodes){
#    my @dead_nodes;
#    $content = curl $url_dead_nodes;
#    foreach my $node (@nodes){
#        unless($content =~ />$node(?:\.$domain_regex)?<\//m){
#            push(@missing_nodes, $node);
#        }
#    }
#
#    $node_count = scalar @nodes;
#    plural($node_count);
#    my $missing_nodes = scalar @missing_nodes;
#    $status = "OK";
#    if(@missing_nodes){
#        if($missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
#            $msg = "'" . join(",", sort @missing_nodes) . "'";
#        } else {
#            $msg = "$missing_nodes/$node_count node$plural";
#        }
#        $msg .= " not";
#    } else {
#        if($node_count <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
#            $msg = "'" . join(",", sort @nodes) . "'";
#        } else {
#            $msg = "$node_count/$node_count checked node$plural";
#        }
#    }
#    $msg .= " found in the active nodes list on the Namenode" . ($verbose ? " at '$host:$port'" : "");
#    if($verbose){
#        if($missing_nodes and $missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
#            $msg .= " ($missing_nodes/$node_count checked node$plural)";
#        } elsif ($node_count <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
#            $msg .= " ($node_count/$node_count checked node$plural)";
#        }
#    }
#    check_thresholds(scalar @missing_nodes);
###############
} elsif($heap){
    #if($content =~ /\bHeap\s+Size\s+is\s+(\d+(?:\.\d+)?)\s+(\wB)\s*\/\s*(\d+(?:\.\d+)?)\s+(\wB)\s+\((\d+(?:\.\d+)?)%\)/io){
    if($content =~ /Heap\s+Memory\s+used\s+(\d+(?:\.\d+)?)\s+(\w+)\s+is\s+(\d+(?:\.\d+)?)%\s+of\s+Commited\s+Heap\s+Memory\s+(\d+(?:\.\d+)?)\s+(\w+)\.\s+Max\s+Heap\s+Memory\s+is\s+(\d+(?:\.\d+)?)\s+(\w+)/){
        $stats{"heap_used"}             = $1;
        $stats{"heap_used_units"}       = $2;
        $stats{"heap_used_pc"}          = $3;
        $stats{"heap_committed"}        = $4;
        $stats{"heap_committed_units"}  = $5;
        $stats{"heap_max"}              = $6;
        $stats{"heap_max_units"}        = $7;
        $stats{"heap_used_bytes"}       = expand_units($stats{"heap_used"}, $stats{"heap_used_units"}, "Heap Used");
        $stats{"heap_committed_bytes"}  = expand_units($stats{"heap_committed"}, $stats{"heap_committed_units"}, "Heap committed");
        $stats{"heap_max_bytes"}        = expand_units($stats{"heap_max"},  $stats{"heap_max_units"},  "Heap Max" );
        $stats{"heap_used_pc_calculated"} =  $stats{"heap_used_bytes"} / $stats{"heap_max_bytes"} * 100;
        if(abs(int($stats{"heap_used_pc_calculated"}) - $stats{"heap_used_pc"}) > 2){
            code_error "mismatch on calculated ($stats{heap_used_pc_calculated}) vs parsed % heap used ($stats{heap_used_pc})";
        }
    } else {
        code_error "failed to find Heap Size in output from Namenode, code error or output from Namenode JSP has changed";
    }
    $status = "OK";
    $msg    = sprintf("Namenode Heap %.2f%% Used of Committed (%s %s used, %s %s committed, %s %s total)", $stats{"heap_used_pc"}, $stats{"heap_used"}, $stats{"heap_used_units"}, $stats{"heap_committed"}, $stats{"heap_committed_units"}, $stats{"heap_max"}, $stats{"heap_max_units"});
    check_thresholds($stats{"heap_used_pc"});
    $msg .= " | 'Namenode Heap % Used'=$stats{heap_used_pc}%;" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "" ) . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "" ) . ";0;100 'Namenode Heap Used'=$stats{heap_used_bytes}B 'NameNode Heap Committed'=$stats{heap_committed_bytes}B";

########
} else {
    usage "error no check specified";
}

quit $status, $msg;
