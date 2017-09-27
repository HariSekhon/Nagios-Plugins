#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-13 19:32:32 +0100 (Sun, 13 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# TODO: check if I can rewrite a version of this via API

my $max_num_down_nodes_to_output = 5;

$DESCRIPTION = "Nagios Plugin to check the number of available cassandra nodes and raise warning/critical on down nodes.

Uses nodetool's status command to determine how many downed nodes there are to compare against the warning/critical thresholds. Reports the addresses of up to $max_num_down_nodes_to_output nodes that are down in verbose mode. Always returns perfdata for graphing the node counts and states.

Can specify a remote host and port otherwise assumes to check via localhost

Tested on Cassandra 1.2, 2.0, 2.1, 2.2, 3.0, 3.5, 3.6, 3.7, 3.9, 3.10, 3.11";

$VERSION = "0.4.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::Cassandra::Nodetool;

set_threshold_defaults(0, 1);

%options = (
    %nodetool_options,
    %thresholdoptions,
);
splice @usage_order, 0, 0, 'nodetool';

get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}status";

vlog2 "fetching cluster nodes information";
my @output = cmd($cmd);

my $up_nodes      = 0;
my $down_nodes    = 0;
my $normal_nodes  = 0;
my $leaving_nodes = 0;
my $joining_nodes = 0;
my $moving_nodes  = 0;

my @down_nodes;
my $node_address;

sub parse_state ($) {
    # Don't know what remote JMX auth failure looks like yet so will go critical on any user/password related message returned assuming that's an auth failure
    check_nodetool_errors($_);
    if(/^[UD][NLJM]\s+($host_regex)/){
        $node_address = $1;
        if(/^U/){
            $up_nodes++;
        } elsif(/^D/){
            $down_nodes++;
            push(@down_nodes, $node_address);
        }
        if(/^.N/){
            $normal_nodes++;
        } elsif(/^.L/){
            $leaving_nodes++;
        } elsif(/^.J/){
            $joining_nodes++;
        } elsif(/^.M/){
            $moving_nodes++;
        } else {
            quit "UNKNOWN", "unrecognized second column for node status, $nagios_plugins_support_msg";
        }
        return 1;
    } elsif($_ =~ $nodetool_status_header_regex){
       # ignore
    } elsif(skip_nodetool_output($_)){
        # ignore
    } else {
        die_nodetool_unrecognized_output($_);
    }
}

foreach(@output){
    parse_state($_);
}

vlog2 "checking node counts and number of nodes down";
if(@down_nodes){
    quit "UNKNOWN", "inconsistent nodes down count vs nodes down addresses, probably a parsing error in parse_state(). $nagios_plugins_support_msg" unless $down_nodes;
    plural $down_nodes;
    vlog2("$down_nodes node$plural down: " . join(", ", @down_nodes) );
}
unless( ($up_nodes + $down_nodes ) == ($normal_nodes + $leaving_nodes + $joining_nodes + $moving_nodes)){
    quit "UNKNOWN", "live+down node counts vs (normal/leaving/joining/moving) nodes are not equal, investigation required";
}

$msg = "$up_nodes nodes up, $down_nodes down";
check_thresholds($down_nodes);
if($verbose and @down_nodes){
    plural scalar @down_nodes;
    $msg .= " [node$plural down: ";
    if(scalar @down_nodes > $max_num_down_nodes_to_output){
        for(my $i; $i < $max_num_down_nodes_to_output; $i++){
            $msg .= ", " . $down_nodes[$i];
        }
        $msg .= " ... ";
    } else {
        $msg .= join(", ", @down_nodes);
    }
    $msg .= "]";
}
$msg .= ", node states: $normal_nodes normal, $leaving_nodes leaving, $joining_nodes joining, $moving_nodes moving";
$msg .= " | nodes_up=$up_nodes nodes_down=$down_nodes";
msg_perf_thresholds();
$msg .= " normal_nodes=$normal_nodes leaving_nodes=$leaving_nodes joining_nodes=$joining_nodes moving_nodes=$moving_nodes";

vlog2;
quit $status, $msg;
