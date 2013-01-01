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

# TODO: needs a little more work and validation

# Nagios Plugin to run various checks against the Hadoop HDFS Cluster via the Namenode JSP pages

# This is a rewrite of the functionality from my previous check_hadoop_dfs.pl plugin
# using the Namenode JSP interface instead of the hadoop dfsadmin -report output
#
# The original plugin is better/tighter than this one, but this one is useful for the following reasons:
# 1. we can run it against the US remotely without needing to adjust the US setup
# 2. it can check Namenode Heap Usage
#
# Caveats:
# 1. Cannot currently detect corrupt or under-replicated blocks since JSP doesn't offer this information
# 2. There are not byte counters, so we can only use the human summary and multiply out, and being a multiplier of a summary figure it's marginally less accurate

# Note: This was created for Apache Hadoop 0.20.2, r911707. If JSP output changes across versions, this plugin will need to be updated to parse the changes

$VERSION = "0.8";

use strict;
use warnings;
use LWP::Simple qw/get $ua/;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use HariSekhonUtils;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $balance         = 0;
my $hdfs_space      = 0;
my $heap            = 0;
my $nodes           = 0;
my $nodes_available = 0;
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
$port = $default_port;

#my $default_warning  = 0;
#my $default_critical = 0;
#$warning  = $default_warning;
#$critical = $default_critical;

%options = (
    "H|host=s"          => [ \$host,            "Namenode to connect to" ],
    "P|port=s"          => [ \$port,            "Namenode port to connect to (defaults to $default_port)" ],
    "s|hdfs-space"      => [ \$hdfs_space,      "Checks % HDFS Space used against given warning/critical thresholds" ],
    "r|replication"     => [ \$replication,     "Checks replication state: under replicated blocks, blocks with corrupt replicas, missing blocks. Warning/critical thresholds apply to under replicated blocks. Corrupt replicas and missing blocks if any raise critical since this can result in data loss" ],
    "heap-usage"        => [ \$heap,            "Check Namenode Heap % Used. Optional % thresholds may be supplied for warning and/or critical" ],
    "b|balance"         => [ \$balance,         "Checks Balance of HDFS Space used % across datanodes is within thresholds. Lists the nodes out of balance in verbose mode" ],
    "m|nodes-available" => [ \$nodes_available, "Checks the number of available datanodes against the given warning/critical thresholds as the lower limits (inclusive). Any dead datanodes raises warning" ],
    "n|nodes=s"         => [ $nodes,            "List of datanodes to expect are available in namenode (non-switch args are appended to this list for convenience)." ],
    "w|warning=s"       => [ \$warning,         "Warning threshold or ran:ge (inclusive)"  ],
    "c|critical=s"      => [ \$critical,        "Critical threshold or ran:ge (inclusive)" ],
);
@usage_order = qw/host port hdfs-space replication balance nodes-available heap-usage warning critical hadoop-bin hadoop-user/;

get_options();

defined($host)  or usage "Namenode host not specified";
$host = isHost($host) || usage "Namenode host invalid, must be hostname/FQDN or IP address";
vlog2 "host:     '$host'";
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
    vlog2 "checking HDFS datanodes available";
    # TODO
    $nodes_available = 1;
}

my $url;
my $url2;
my %nodes;
my @nodes;
unless($hdfs_space or $replication or $balance or $nodes_available or $heap){
    usage "must specify one of --hdfs-space / --replication / --balance / --nodes-available / --heap to check";
}
if($hdfs_space + $replication + $balance + $nodes_available + $heap > 1){
    usage "can only check one of HDFS space used %, replication, HDFS balance, datanodes available at one time, otherwise the warning/critical thresholds will conflict or require a large number of switches";
}
if($nodes_available){
    $warning  = 0 unless $warning;
    $critical = 0 unless $critical;
    validate_thresholds(1, 1, {
                            "simple"   => "lower",
                            "integer"  => 1
                            });
} else {
    validate_thresholds(1, 1);
}

$url = "http://$host:$port/$namenode_urn";
if($balance){
    $url2 = "http://$host:$port/$namenode_urn_live_nodes";
}

vlog2;
set_timeout();
#$ua->timeout($timeout);

my $content = curl $url;

sub parse_dfshealth {
    # Note: This was created for Apache Hadoop 0.20.2, r911707. If they change this page across versions, this plugin will need to be updated to parse the changes
    vlog2 "parsing Namenode dfs health output";

    my $regex_td = '\s*(?:<\/a>\s*)?<td\s+id="\w+">\s*:\s*<td\s+id="\w+">\s*';
    my $regex_configured_capacity = qr/>\s*Configured Capacity$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    my $regex_dfs_used            = qr/>\s*DFS Used$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    my $regex_dfs_used_pc         = qr/>\s*DFS Used%\s*<td\s+id="\w+">\s*:\s*<td\s+id="\w+">\s*(\d+(?:\.\d+)?)\s*%\s*</o;
    my $regex_live_nodes          = qr/>\s*Live Nodes$regex_td(\d+)\s*</o;
#    my $regex_present_capacity    = qr/>\s*Present Capacity$regex_td(\d+(?:\.\d+)?)\s(\w+)\s*</o;
    if($content =~ /$regex_live_nodes/o){
        $dfs{"datanodes_available"} = $1;
    }
    # These multiplier calculations are slightly less accurate than the actual amount given by the hadoop dfsadmin -report that my other plugin uses but since the web page doesn't give the bytes count I have to estimate it by plain multiplier (JSP pages are only giving the rounded summary that I am then having to multiply
    if($content =~ /$regex_dfs_used/o){
        $dfs{"dfs_used_human"} = $1;
        $dfs{"dfs_used"} = expand_units($1, $2, "DFS Used");
    }
    if($content =~ /$regex_dfs_used_pc/o){
        $dfs{"dfs_used_pc"} = $1;
    }
    if($content =~ /$regex_configured_capacity/o){
        $dfs{"configured_capacity_human"} = $1;
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
            dfs_used
            dfs_used_human
            dfs_used_pc
            datanodes_available
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
    $content = curl $url2;
    vlog2 "parsing Namenode datanode % usage\n";
    if($content =~ />\s*Live Datanodes\s*:*\s*(\d+)\s*</){
        $dfs{"datanodes_available"} = $1;
    } else {
        quit "UNKNOWN", "couldn't find Live Datanodes in output from $url";
    }
    my %datanodes_used_pc;
    my $regex_datanode_used_pc = qr/<td\s+class="name"><a[^>]+>\s*($hostname_regex|$ip_regex)\s*<\/a>.+<td\s+align="right"\s+class="pcused">\s*(\d+(?:\.\d+)?)\s*</o;
    #print "regex datanode used pc: $regex_datanode_used_pc\n";
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
    $msg = sprintf("%.2f%% HDFS space used on %d available datanodes", $dfs{"dfs_used_pc"}, $dfs{"datanodes_available"});
    check_thresholds($dfs{"dfs_used_pc"});
    # JSP Pages don't give Present Capacity
    #$msg .= " | 'HDFS Space Used'=$dfs{dfs_used_pc}%;$thresholds{warning}{upper};$thresholds{critical}{upper} 'HDFS Used Capacity'=$dfs{dfs_used}B;;0;$dfs{configured_capacity} 'HDFS Present Capacity'=$dfs{present_capacity}B 'HDFS Configured Capacity'=$dfs{configured_capacity}B 'Datanodes Available'=$dfs{datanodes_available}";
    $msg .= " | 'HDFS Space Used'=$dfs{dfs_used_pc}%;$thresholds{warning}{upper};$thresholds{critical}{upper} 'HDFS Used Capacity'=$dfs{dfs_used}B;;0;$dfs{configured_capacity} 'HDFS Configured Capacity'=$dfs{configured_capacity}B 'Datanodes Available'=$dfs{datanodes_available}";

######################
# TODO:
} elsif($replication){
    # TODO: dfsadmin report currently shows in US cluster 96 missing, 96 under-replicated and 9 corrupt blocks, yet only missing appear in JSP interface. Do not use --replication feature until determined why. Other plugin check_hadoop_dfs.pl is better at this time as it'll detect this properly. If JSP doesn't serve this information we're stuck on this point
    #quit "UNKNOWN", "JSP doesn't give corrupt and under-replicated blocks at time of coding, cannot use this feature yet, use the other better check_hadoop_dfs.pl plugin";
    # TODO: check this when we actually have corrupt blocks
    if($content =~ /(\d+) corrupt blocks/){
        $dfs{"corrupt_blocks"} = $1;
    }
    if($content =~ /(\d+) missing blocks/){
        $dfs{"missing_blocks"} = $1;
    }
    # TODO: check this when we actually have under-replicated blocks
    if($content =~ /(\d+) under-replicated blocks/){
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
    #check_thresholds($dfs{"under_replicated_blocks"});
    $msg = sprintf("%d missing blocks detected (JSP doesn't show us corrupt or under-replicated blocks at this time!)", $dfs{"missing_blocks"});
    #if($dfs{"corrupt_blocks"} or $dfs{"missing_blocks"}){
    if($dfs{"missing_blocks"}){
        critical;
        #$msg = "corrupt/missing blocks detected. $msg";
    }
    #$msg .= " | 'under replicated blocks'=$dfs{under_replicated_blocks};$thresholds{warning}{upper};$thresholds{critical}{upper} 'corrupt blocks'=$dfs{corrupt_blocks} 'missing blocks'=$dfs{missing_blocks}";
    $msg .= " | 'missing blocks'=$dfs{missing_blocks}";

################
# TODO:
} elsif($nodes_available){
    my @missing_nodes;
    foreach my $node (@nodes){
        unless($content =~ /<td>$node(?:\.$domain_regex)?<\/td>/){
            push(@missing_nodes, $node);
        }
    }

    $nodes_available = scalar @nodes;
    plural($nodes_available);
    my $missing_nodes = scalar @missing_nodes;
    $status = "OK";
    if($missing_nodes){
        if($missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg = "'" . join(",", sort @missing_nodes) . "'";
        } else {
            $msg = "$missing_nodes/$nodes_available node$plural";
        }
        $msg .= " not";
    } else {
        if($nodes_available <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg = "'" . join(",", sort @nodes) . "'";
        } else {
            $msg = "$nodes_available/$nodes_available checked node$plural";
        }
    }
    $msg .= " found in the active machines list on the Namenode" . ($verbose ? " at '$host:$port'" : "");
    if($verbose){
        if($missing_nodes and $missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg .= " ($missing_nodes/$nodes_available checked node$plural)";
        } elsif ($nodes_available <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg .= " ($nodes_available/$nodes_available checked node$plural)";
        }
    }
    check_thresholds($missing_nodes);
###############
} elsif($heap){
    if($content =~ /\bHeap\s+Size\s+is\s+(\d+(?:\.\d+)?)\s+(\wB)\s*\/\s*(\d+(?:\.\d+)?)\s+(\wB)\s+\((\d+(?:\.\d+)?)%\)/io){
        $stats{"heap_used"}       = $1;
        $stats{"heap_used_units"} = $2;
        $stats{"heap_max"}        = $3;
        $stats{"heap_max_units"}  = $4;
        $stats{"heap_used_pc"}    = $5;
        $stats{"heap_used_bytes"} = expand_units($stats{"heap_used"}, $stats{"heap_used_units"}, "Heap Used");
        $stats{"heap_max_bytes"}  = expand_units($stats{"heap_max"},  $stats{"heap_max_units"},  "Heap Max" );
        $stats{"heap_used_pc_calculated"} =  $stats{"heap_used_bytes"} / $stats{"heap_max_bytes"} * 100;
        unless(sprintf("%d", $stats{"heap_used_pc_calculated"}) eq sprintf("%d", $stats{"heap_used_pc"})){
            code_error "mismatch on calculated vs parsed % heap used";
        }
    } else {
        code_error "failed to find Heap Size in output from Namenode, code error or output from Namenode JSP has changed";
    }
    $status = "OK";
    $msg    = sprintf("Namenode Heap %.2f%% Used (%s %s used, %s %s total)", $stats{"heap_used_pc"}, $stats{"heap_used"}, $stats{"heap_used_units"}, $stats{"heap_max"}, $stats{"heap_max_units"});
    check_thresholds($stats{"heap_used_pc"});
    $msg .= " | 'Namenode Heap % Used'=$stats{heap_used_pc}%;" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "" ) . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "" ) . ";0;100 'Namenode Heap Used'=$stats{heap_used_bytes}B";

########
} else {
    if($content =~ /<tr><th>Maps<\/th><th>Reduces<\/th><th>Total Submissions<\/th><th>Nodes<\/th><th>Map Task Capacity<\/th><th>Reduce Task Capacity<\/th><th>Avg\. Tasks\/Node<\/th><th>Blacklisted Nodes<\/th><\/tr>\n<tr><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+)<\/td><td><a href="machines\.jsp\?type=active">(\d+)<\/a><\/td><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+(?:\.\d+)?)<\/td><td><a href="machines\.jsp\?type=blacklisted">(\d+)<\/a><\/td><\/tr>/mi){
        $stats{"maps"}                  = $1;
        $stats{"reduces"}               = $2;
        $stats{"total_submissions"}     = $3;
        $stats{"nodes"}                 = $4;
        $stats{"map_task_capacity"}     = $5;
        $stats{"reduce_task_capacity"}  = $6;
        $stats{"avg_tasks_node"}        = $7;
        $stats{"blacklisted_nodes"}     = $8;
    }
    foreach(qw/maps reduces total_submissions nodes map_task_capacity reduce_task_capacity avg_tasks_node blacklisted_nodes/){
        unless(defined($stats{$_})){
            vlog2;
            quit "UNKNOWN", "failed to find $_ in Namenode output";
        }
        vlog2 "stats $_ = $stats{$_}";
    }
    vlog2;

    $status = "OK";
    $msg = sprintf("%d MapReduce nodes available, %d blacklisted nodes", $stats{"nodes"}, $stats{"blacklisted_nodes"});
    $thresholds{"warning"}{"lower"}  = 0 unless $thresholds{"warning"}{"lower"};
    $thresholds{"critical"}{"lower"} = 0 unless $thresholds{"critical"}{"lower"};
    check_thresholds($stats{"nodes"});
    # TODO: This requires a pnp4nagios config for Maps and Tasks which are basically counters
    $msg .= sprintf(" | 'MapReduce Nodes'=%d;%d;%d 'Blacklisted Nodes'=%d Maps=%d Reduces=%d 'Total Submissions'=%d 'Map Task Capacity'=%d 'Reduce Task Capacity'=%d 'Avg. Tasks/Node'=%.2f",
                        $stats{"nodes"},
                        $thresholds{"warning"}{"lower"},
                        $thresholds{"critical"}{"lower"},
                        $stats{"blacklisted_nodes"},
                        $stats{"maps"},
                        $stats{"reduces"},
                        $stats{"total_submissions"},
                        $stats{"map_task_capacity"},
                        $stats{"reduce_task_capacity"},
                        $stats{"avg_tasks_node"}
                   );

    if($stats{"blacklisted_nodes"}){
        critical;
    }
}

quit $status, $msg;
