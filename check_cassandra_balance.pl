#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-04 01:52:54 +0000 (Mon, 04 Nov 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the balance of ownership of tokens across nodes

Uses nodetool's status command to find token % across all nodes and alerts if the largest difference is greater than warning/critical thresholds. Returns perfdata of the max imbalance % for graphing.

Use --verbose mode to also output max & min node % token ownership and rack information

Can specify a remote host and port otherwise assumes to check via localhost

Written and tested against Cassandra 2.0.1 and 2.0.9, DataStax Community Edition";

$VERSION = "0.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Cassandra::Nodetool;

set_threshold_defaults(10, 20);

my $exclude_joining_leaving = 0;

%options = (
    %nodetool_options,
    "exclude-joining-leaving" => [ \$exclude_joining_leaving,   "Exclude Joining/Leaving nodes from the balance calculation (Downed nodes are already excluded)" ],
    %thresholdoptions,
);
@usage_order = qw/nodetool host port user password exclude-joining-leaving warning critical/;

get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 0, "positive" => 1, "max" => "100" });

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}status";

vlog2 "fetching cluster nodes information";
my @output = cmd($cmd);
#               name                  %    rack
my @max_node = ("uninitialized_node", 0,   "uninitialized_rack");
my @min_node = ("uninitialized_node", 100, "uninitialized_rack");
my $node_count = 0;
foreach(@output){
    check_nodetool_errors($_);
    if($_ =~ $nodetool_status_header_regex){
       next;
    }
    # Only consider up nodes
    next if(/^D[NJLM]\s+/);
    next if($exclude_joining_leaving and /^U[JL]\s+/);
    if(/^[^\s]+\s+([^\s]+)\s+[^\s]+(?:\s+[A-Za-z][A-Za-z])?\s+[^\s]+\s+(\d+(?:\.\d+)?)\%\s+[^\s]+\s+([^\s]+)/){
        $node_count++;
        my $node       = $1;
        my $percentage = $2;
        my $rack       = $3;
        if($percentage > $max_node[1]){
            @max_node = ($node, $percentage, $rack);
        }
        if($percentage < $min_node[1]){
            @min_node = ($node, $percentage, $rack);
        }
    } elsif(skip_nodetool_output($_)){
        # ignore
    } else {
        die_nodetool_unrecognized_output($_);
    }
}
if($node_count < 1){
    quit "UNKNOWN", "no nodes found!";
} elsif($node_count == 1){
    @min_node = @max_node;
}

my $max_diff_percentage = sprintf("%.2f", $max_node[1] - $min_node[1]);

plural $node_count;
$msg = "$max_diff_percentage% max imbalance between $node_count cassandra node$plural"; 
check_thresholds($max_diff_percentage);
$msg .= ", max node: $max_node[1]% [$max_node[0] ($max_node[2])], min node: $min_node[1]% [$min_node[0] ($min_node[2])]" if $verbose;
$msg .= " | 'max_%_imbalance'=$max_diff_percentage%";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
