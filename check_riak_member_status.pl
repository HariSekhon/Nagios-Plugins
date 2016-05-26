#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-06-13 23:15:35 +0100 (Sat, 13 Jun 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check Riak member status via riak-admin

Checks number of down nodes against thresholds

Designed to be run on a Riak node over NRPE

Tested on Riak 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Riak;

set_threshold_defaults(0, 1);

%options = (
    %riak_admin_path_option,
    %thresholdoptions,
);
@usage_order = qw/riak-admin-path warning critical/;

get_options();
validate_thresholds(1, 1, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1});

set_timeout();

get_riak_admin_path();

$status = "OK";

my $cmd = "riak-admin member-status";

vlog2 "running $cmd";
my @output = cmd($cmd, 1);
vlog2 "checking $cmd results";

my $found_header = 0;
my %nodes;
# valid     100.0%      --      'riak@127.0.0.1'
my $node_regex = '^([^\s]+)\s+[^\s]+\s+[^\s]+\s+([^\s]+)\s*$';
my $node;
my ($valid, $leaving, $exiting, $joining, $down);
sub clean_nodename($){
    my $node = shift;
    $node =~ s/'//g;
    $node =~ s/^riak\@//;
    return $node;
}

foreach my $line (@output){
    if($line =~ /^=====/ or
       $line =~ /^-----/){
        next;
    # Status     Ring    Pending    Node
    } elsif($line =~ /^Status\s+Ring\s+Pending\s+Node\s*$/i){
        $found_header = 1;
    } elsif($line =~ /$node_regex/i){
        unless(defined($nodes{$1})){
            $nodes{$1} = ();
        }
        push(@{$nodes{$1}}, clean_nodename($2));
    # Valid:1 / Leaving:0 / Exiting:0 / Joining:0 / Down:0
    # making this regex a bit flexible intentionally in case the output changes a bit
    } elsif($line =~ /^Valid\s*:\s*(\d+).+\bLeaving\s*:\s*(\d+).+\bExiting\s*:\s*(\d+).+\bJoining\s*:\s*(\d+).+\bDown\s*:\s*(\d+)$/){
        $valid   = $1;
        $leaving = $2;
        $exiting = $3;
        $joining = $4;
        $down    = $5;
    } else {
        quit "UNKNOWN", "unrecognized line in output: '$line'. $nagios_plugins_support_msg";
    }
}
unless($found_header){
    quit "UNKNOWN", "header not found. $nagios_plugins_support_msg";
}
my $node_count = 0;
foreach my $status_type (keys %nodes){
    $node_count += scalar @{$nodes{$status_type}};
}
plural $node_count;
vlog2 "$node_count node$plural found";
unless($node_count){
    quit "UNKNOWN", "failed to parse specific nodes, $nagios_plugins_support_msg";
}

$msg = "valid: $valid, leaving: $leaving, exiting: $exiting, joining: $joining, down: $down";

unless($valid + $leaving + $exiting + $joining + $down > 0){
    unknown;
    $msg = "No valid node states detected! $msg";
}

foreach my $status_type (sort keys %nodes){
    vlog2 "$status_type nodes: " . join(", ", @{$nodes{$status_type}});
}


check_thresholds($down);
if($verbose){
    $msg .= " {";
    foreach my $status_type (sort keys %nodes){
        $msg .= "$status_type=[" . join(",", @{$nodes{$status_type}}) . "], ";
    }
    $msg =~ s/, $//;
    $msg .= "}";
}
$msg .= " | valid=$valid leaving=$leaving exiting=$exiting joining=$joining down=$down";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
