#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-10-05 14:00:09 +0100 (Fri, 05 Oct 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# TODO: switch this to use /jmx as /metrics doesn't expose non-heap max

$DESCRIPTION = "Nagios Plugin to run various checks against a Hadoop MapReduce cluster by querying the JobTracker

This is a consolidation/rewrite of two of my previous plugins for MapReduce cluster checks

Runs in 1 of 3 modes:

1. available MapReduce nodes and detect any Blacklisted nodes
   - any Blacklisted nodes raises Critical
   - checks optional thresholds for the minimum number of available MapReduce nodes available (default 0 == disabled)
2. detect which MapReduce nodes aren't active in the JobTracker if given a node list
   - checks optional thresholds for the maximum number of missing nodes from the specified list (default 0 == CRITICAL on any missing, you may want to set these thresholds higher)
3. checks the JobTracker Heap % Used

Originally written on old vanilla Apache Hadoop 0.20.x, backwards untested rewrite for CDH 4.3 (2.0.0-mr1)

Seriously recommend you consider using check_hadoop_cloudera_manager_metrics.pl instead if possible (disclaimer I worked for Cloudera but seriously it's better it uses the CM API instead of scraping output which can break betweens versions and requires more maintenance)";

$VERSION = "0.9.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

# this is really just for constraining the size of the output printed
my $MAX_NODES_TO_DISPLAY_AS_ACTIVE  = 5;
my $MAX_NODES_TO_DISPLAY_AS_MISSING = 30;

my $nodes;
my $heap;
my $non_heap;
# originally scraped the HTML in Apache 0.20.x, instead using metrics page now as it's clearner
#my $jobtracker_urn                  = "jobtracker.jsp";
my $jobtracker_urn                  = "metrics";
my $jobtracker_urn_machines_active  = "machines.jsp?type=active";

set_port_default(50030);

my $default_warning  = 0;
my $default_critical = 0;
$warning  = $default_warning;
$critical =  $default_critical;

env_creds(["HADOOP_JOBTRACKER", "HADOOP"], "Hadoop JobTracker");

%options = (
    %hostoptions,
    "n|nodes=s"        => [ \$nodes,        "Optional list of nodes to check are alive in the JobTracker (non-switch args are appended to this list for convenience)" ],
    "heap-usage"       => [ \$heap,         "Check JobTracker Heap % Used. There is a bug in the JobTracker UI where it's showing committed instead of used so after some run time it always appears full" ],
    #"non-heap-usage"   => [ \$non_heap,     "Check JobTracker Non Heap % Used. Optional % thresholds may be supplied for warning/critical" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive) for min number of available nodes or max missing/inactive nodes if node list is given (defaults to $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive) for min number of available nodes or max missing/inactive nodes if node list is given (defaults to $default_critical)" ],
);
@usage_order = qw/host port nodes heap-usage non-heap-usage warning critical/;

get_options();

defined($host)  or usage "JobTracker host not specified";
if($progname eq "check_hadoop_mapreduce_nodes_active.pl"){
    defined($nodes) or usage "Node list not specified";
}
if($nodes and ($heap or $non_heap)){
    usage "Cannot specify both --nodes and --[non-]heap-usage";
}
$host = isHost($host) || usage "JobTracker host invalid, must be hostname/FQDN or IP address";
vlog_option "host", "'$host'";
$host = validate_resolvable($host);
$port = validate_port($port);

my $url;
my %nodes;
my @nodes;
my %stats;
if(defined($nodes)){
    $url = "http://$host:$port/$jobtracker_urn_machines_active";
    # this uniqs the list of nodes given
    %nodes = map { $_ => 1 } split(/[,\s]+/, $nodes);
    @nodes = sort keys %nodes;
    push(@nodes, @ARGV);
    scalar @nodes or usage "node list empty";
    foreach my $node (@nodes){
        $node = isHost($node) || usage "Node name '$node' invalid, must be hostname/FQDN or IP address";
    }
    vlog2 "nodes:    '" . join(",", @nodes) . "'";
    validate_thresholds(undef, undef, {
                                        "positive" => 1,
                                        "integer"  => 1
                                        } );
} elsif($heap or $non_heap){
    $url = "http://$host:$port/$jobtracker_urn";
    validate_thresholds(1, 1, {
                                "simple"   => "upper",
                                "positive" => 1,
                                "integer"  => 0,
                                "max"      => 100
                                });
} else {
    $url = "http://$host:$port/$jobtracker_urn";
    validate_thresholds(undef, undef, {
                                        "simple"   => "lower",
                                        "positive" => 1,
                                        "integer"  => 1
                                        });
}

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $content = curl $url, "JobTracker";

# Note: This was created for Apache Hadoop 0.20.2, r911707. If they change this page across versions, this plugin will need to be updated
vlog2 "parsing output from JobTracker\n";

my @stats;
sub check_stats_parsed(){
    foreach(@stats){
        unless(defined($stats{$_})){
            vlog2;
            quit "UNKNOWN", "failed to find $_ in JobTracker output";
        }
        vlog2 "stats $_ = $stats{$_}";
    }
    vlog2;
}

sub parse_stats(){
    foreach my $line (split("\n", $content)){
        foreach my $stat (@stats){
            if($line =~ /^\s*$stat\s*=\s*(\d+(?:\.\d+)?)\s*$/){
                $stats{$stat} = $1;
                last;
            }
        }
    }
    check_stats_parsed();
}

if(defined($nodes)){
    my @missing_nodes;
    foreach my $node (@nodes){
        unless($content =~ /<td>$node(?:\.$domain_regex)?<\/td>/){
            push(@missing_nodes, $node);
        }
    }

    $nodes = scalar @nodes;
    plural($nodes);
    my $missing_nodes = scalar @missing_nodes;
    $status = "OK";
    if($missing_nodes){
        if($missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg = "'" . join(",", sort @missing_nodes) . "'";
        } else {
            $msg = "$missing_nodes/$nodes node$plural";
        }
        $msg .= " not";
    } else {
        if($nodes <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg = "'" . join(",", sort @nodes) . "'";
        } else {
            $msg = "$nodes/$nodes checked node$plural";
        }
    }
    $msg .= " found in the active machines list on the JobTracker" . ($verbose ? " at '$host:$port'" : "");
    if($verbose){
        if($missing_nodes and $missing_nodes <= $MAX_NODES_TO_DISPLAY_AS_MISSING){
            $msg .= " ($missing_nodes/$nodes checked node$plural)";
        } elsif ($nodes <= $MAX_NODES_TO_DISPLAY_AS_ACTIVE){
            $msg .= " ($nodes/$nodes checked node$plural)";
        }
    }
    check_thresholds($missing_nodes);

} elsif($heap or $non_heap){
#    foreach(split("\n", $content)){
#        if(/Cluster Summary \(Heap Size is (\d+(?:\.\d+)?) (.B)\/(\d+(?:\.\d+)?) (.B)\)/i){
#            $stats{"heap_used"}       = $1;
#            $stats{"heap_used_units"} = $2;
#            $stats{"heap_max"}        = $3;
#            $stats{"heap_max_units"}  = $4;
#            $stats{"heap_used_bytes"} = expand_units($stats{"heap_used"}, $stats{"heap_used_units"}, "Heap Used");
#            $stats{"heap_max_bytes"}  = expand_units($stats{"heap_max"},  $stats{"heap_max_units"},  "Heap Max" );
#            $stats{"heap_used_pc"}    = sprintf("%.2f", $stats{"heap_used_bytes"} / $stats{"heap_max_bytes"} * 100);
#            last;
#        }
#    }
#    foreach(qw/heap_used heap_used_units heap_max heap_max_units heap_used_bytes heap_max_bytes heap_used_pc/){
    my $heap_str;
    if($heap){
        $heap_str = "Heap";
        @stats = qw/memHeapUsedM maxMemoryM/;
    } elsif($non_heap){
        $heap_str = "Non Heap";
        @stats = qw/memNonHeapUsedM maxNonMemoryM/; #max non heap memory isn't exposed in /metrics, switch to /jmx
    } else {
        code_error "failed to determine heap vs non-heap late in code";
    }
    parse_stats();
    #$stats{"heap_used_pc"} = $stats{"memHeapUsedM"} / $stats{"maxMemoryM"} * 100;
    $stats{"${heap_str}_used_pc"} = $stats{$stats[0]} / $stats{$stats[1]} * 100;
    $status = "OK";
    #$msg    = sprintf("JobTracker Heap %.2f%% Used (%s %s used, %s %s total)", $stats{"heap_used_pc"}, $stats{"heap_used"}, $stats{"heap_used_units"}, $stats{"heap_max"}, $stats{"heap_max_units"});
    $msg    = sprintf("JobTracker $heap_str %.2f%% Used (%s MB used, %s MB total)", $stats{"${heap_str}_used_pc"}, $stats{$stats[0]}, $stats{$stats[1]});
    check_thresholds($stats{"${heap_str}_used_pc"});
    #$msg .= " | 'JobTracker Heap % Used'=$stats{heap_used_pc}%;" . ($thresholds{warning}{upper} ? $thresholds{warning}{upper} : "" ) . ";" . ($thresholds{critical}{upper} ? $thresholds{critical}{upper} : "" ) . ";0;100 'JobTracker Heap Used'=$stats{heap_used_bytes}B";
    $msg .= " | 'JobTracker $heap_str % Used'=" . $stats{"${heap_str}_used_pc"} . "%" . msg_perf_thresholds(1) . "0;100 'JobTracker $heap_str Used'=$stats{$stats[0]}MB";
} else {
    # Old Apache 0.20.x
    #if($content =~ /<tr><th>Maps<\/th><th>Reduces<\/th><th>Total Submissions<\/th><th>Nodes<\/th><th>Map Task Capacity<\/th><th>Reduce Task Capacity<\/th><th>Avg\. Tasks\/Node<\/th><th>Blacklisted Nodes<\/th><\/tr>\n<tr><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+)<\/td><td><a href="machines\.jsp\?type=active">(\d+)<\/a><\/td><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+(?:\.\d+)?)<\/td><td><a href="machines\.jsp\?type=blacklisted">(\d+)<\/a><\/td><\/tr>/mi or
#        $stats{"maps"}                  = $1;
#        $stats{"reduces"}               = $2;
#        $stats{"total_submissions"}     = $3;
#        $stats{"nodes"}                 = $4;
#        $stats{"map_task_capacity"}     = $5;
#        $stats{"reduce_task_capacity"}  = $6;
#        $stats{"avg_tasks_node"}        = $7;
#        $stats{"blacklisted_nodes"}     = $8;
    # Apache 2.0.x MR1 from CDH 4.3, unfinished, switch to /metrics instead
#       $content =~ /<tr><th>Running Map Tasks<\/th><th>Running Reduce Tasks<\/th><th>Total Submissions<\/th><th>Nodes<\/th><th>Occupied Map Slots<\/th><th>Occupied Reduce Slots<\/th><th>Reserved Map Slots<\/th><th>Reserved Reduce Slots<\/th><th>Map Task Capacity<\/th><th>Reduce Task Capacity<\/th><th>Avg. Tasks\/Node<\/th><th>Blacklisted Nodes<\/th><th>Excluded Nodes<\/th><\/tr>
#<tr><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+)<\/td><td><a href="machines\.jsp?type=active">(\d+)<\/a><\/td><td>\d+<\/td><td>\d+<\/td><td>\d+<\/td><td>\d+<\/td><td>(\d+)<\/td><td>(\d+)<\/td><td>(\d+(?:\.\d+)?)<\/td><td><a href="machines.jsp?type=blacklisted">(\d+)<\/a><\/td><td><a href="machines.jsp?type=excluded">\d+<\/a><\/td><\/tr>/mi){
#    my $stats_map = (
#        "maps"                  => "running_maps",
#        "reduces"               => "running_reduces",
#        "total_submissions"     => "jobs_submitted",
#        "nodes"                 => "trackers",
#        "map_task_capacity"     => "map_slots"
#        "reduce_task_capacity"  => "reduce_slots",
#        # not supplied in /metrics
#        #"avg_tasks_node"        =>
#        "blacklisted_nodes"     => "trackers_blacklisted",
#    );
    @stats = qw/jobs_submitted map_slots reduce_slots running_maps running_reduces trackers trackers_blacklisted/;
    parse_stats();
    #foreach(qw/maps reduces total_submissions nodes map_task_capacity reduce_task_capacity avg_tasks_node blacklisted_nodes/){
    $stats{"avg_tasks_node"} = ($stats{"map_slots"} + $stats{"reduce_slots"}) / $stats{"trackers"};

    $status = "OK";
    #$msg = sprintf("%d MapReduce nodes available, %d blacklisted nodes", $stats{"nodes"}, $stats{"blacklisted_nodes"});
    $msg = sprintf("%d MapReduce nodes available, %d blacklisted nodes", $stats{"trackers"}, $stats{"trackers_blacklisted"});
    $thresholds{"warning"}{"lower"}  = 0 unless $thresholds{"warning"}{"lower"};
    $thresholds{"critical"}{"lower"} = 0 unless $thresholds{"critical"}{"lower"};
    check_thresholds($stats{"trackers"});
    # TODO: This requires a pnp4nagios config for Maps and Tasks which are basically counters
    $msg .= sprintf(" | 'MapReduce Nodes'=%d;%d;%d 'Blacklisted Nodes'=%d Maps=%d Reduces=%d 'Total Submissions'=%d 'Map Task Capacity'=%d 'Reduce Task Capacity'=%d 'Avg. Tasks/Node'=%.2f",
                        $stats{"trackers"},
                        $thresholds{"warning"}{"lower"},
                        $thresholds{"critical"}{"lower"},
                        $stats{"trackers_blacklisted"},
                        $stats{"running_maps"},
                        $stats{"running_reduces"},
                        $stats{"jobs_submitted"},
                        $stats{"map_slots"},
                        $stats{"reduce_slots"},
                        $stats{"avg_tasks_node"}
                   );

    if($stats{"trackers_blacklisted"}){
        critical;
    }
}

quit $status, $msg;
