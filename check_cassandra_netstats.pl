#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-15 04:56:49 +0100 (Tue, 15 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to fetch Cassandra's netstats per node by parsing 'nodetool netstats'.

Checks Pending commands and responses against warning/critical thresholds.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Tested on Cassandra 1.2, 2.0, 2.1, 2.2, 3.0, 3.5, 3.6, 3.7, 3.9, 3.10, 3.11";

$VERSION = "0.7.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Cassandra::Nodetool;

set_threshold_defaults(5, 10);

%options = (
    %nodetool_options,
    %thresholdoptions,
);
splice @usage_order, 0, 0, 'nodetool';

get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}netstats";

vlog2 "fetching net stats";
my @output = cmd($cmd);

foreach(@output){
    skip_nodetool_output($_) and next;
    check_nodetool_errors($_);
}
my $i = 0;
while(skip_nodetool_output($output[$i])){
    $i++;
}
while($i < scalar @output and $output[$i] !~ /Pool\s+Name\s+Active\s+Pending\s+Completed(?:\s+Dropped)?\s*$/i){
    $i++;
}
$i++;
if($i >= scalar @output){
    quit "UNKNOWN", "failed to find stats header during parsing";
}
my %stats;
foreach(; $i < scalar @output; $i++){
    $output[$i] =~ /^\s*$/ and $i++ and last;
    $output[$i] =~ /^(\w+(?:\s[A-Za-z]+)?)\s+(n\/a|\d+)\s+(\d+)\s+(\d+)(?:\s+(n\/a|\d+))?\s*$/i or die_nodetool_unrecognized_output($output[$i]);
    my $type = $1;
    my $active = $2;
    my $pending = $3;
    my $completed = $4;
    my $dropped = undef;
    if(defined($5) and $5 ne "n/a"){
        $dropped = $5;
    }
    vlog3 "type = $type";
    vlog3 "active = $active";
    vlog3 "pending = $pending";
    vlog3 "completed = $completed";
    vlog3 "dropped = $dropped\n" if defined($dropped);
    $type =~ s/[^A-Za-z0-9]/_/g;
    $stats{$type}{"Active"}    = ( $active eq "n/a" ? 0 : $active );
    $stats{$type}{"Pending"}   = $pending;
    $stats{$type}{"Completed"} = $completed;
    $stats{$type}{"Dropped"}   = $dropped if defined($dropped);
}

%stats or quit "UNKNOWN", "no stats found from cassandra netstats. $nagios_plugins_support_msg";

my $msg2;
my $msg3 = "";
my ($thresholds_ok, $thresholds_msg);
#foreach my $type (qw/Commands Responses/){
foreach my $type (sort keys %stats){
    # Commands and Responses not available in Cassandra 2.2 in Docker...
    #defined($stats{$type}) or quit "'$type' not found in netstats output. $nagios_plugins_support_msg";
    defined($stats{$type}) or next;
    foreach my $type2 (qw/Active Pending Completed Dropped/){
        #defined($stats{$type}{$type2}) or quit "'$type' => '$type2' not found in netstats output. $nagios_plugins_support_msg";
        defined($stats{$type}{$type2}) or next;
        $msg2 = "${type}_$type2=$stats{$type}{$type2}";
        $msg3 .= $msg2;
        $msg2 .= " ";
        if($type2 eq "Pending"){
            ($thresholds_ok, $thresholds_msg) = check_thresholds($stats{$type}{$type2}, 1);
            unless($thresholds_ok){
                $msg2 = uc $msg2;
            }
            $msg3 .= msg_perf_thresholds(1);
        } elsif($type2 eq "Completed" or $type2 eq "Dropped"){
            $msg3 .= "c";
        }
        $msg3 .= " ";
        $msg .= $msg2;
    }
}
$msg  =~ s/\s$//;
if($verbose or $status ne "OK"){
    msg_thresholds();
}
$msg3 or quit "UNKNOWN", "no stats collected from cassandra netstats. $nagios_plugins_support_msg";
$msg .= " | $msg3";

vlog2;
quit $status, $msg;
