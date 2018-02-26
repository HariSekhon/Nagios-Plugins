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

$DESCRIPTION = "Nagios Plugin to fetch Cassandra's thread pool stats per node by parsing 'nodetool tpstats'.

Checks Pending/Blocked operations against warning/critical thresholds.
Check the baseline first and then set appropriate thresholds since a build up of Pending/Blocked operations is indicative of performance problems.

Also returns Active and Dropped operations with perfdata for graphing.

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

set_threshold_defaults(0, 0);

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
my $cmd     = "${nodetool} ${options}tpstats";

vlog2 "fetching threadpool stats";
my @output = cmd($cmd);

foreach(@output){
    skip_nodetool_output($_) and next;
    check_nodetool_errors($_);
}
my $i = 0;
while(skip_nodetool_output($output[$i])){
    $i++;
}
$output[$i] =~ /Pool\s+Name\s+Active\s+Pending\s+Completed\s+Blocked\s+All time blocked\s*$/i or die_nodetool_unrecognized_output($output[$i]);
$i++;
my @stats;
foreach(; $i < scalar @output; $i++){
    $output[$i] =~ /^\s*$/ and $i++ and last;
    $output[$i] =~ /^(\w[\w\#-]+(?:\s[A-Za-z]+)?)\s+(\d+)\s+(\d+)\s+(\d+)(?:\s+(\d+)\s+(\d+))?\s*$/ or die_nodetool_unrecognized_output($output[$i]);
    push(@stats,
        (
            { "$1_Blocked"          => $5, },
            { "$1_Pending"          => $3, },
            { "$1_Active"           => $2, },
            #{ "$1_Completed"        => $4, },
            #{ "$1_All_time_blocked" => $6, },
        )
    );
}
foreach(; $i < scalar @output; $i++){
    next if $output[$i] =~ /^\s*$/;
    last;
}

my $format_changed_err = "unrecognized line '%s', nodetool output format may have changed, aborting. ";
sub die_format_changed($){
    quit "UNKNOWN", sprintf("$format_changed_err$nagios_plugins_support_msg", $_[0]);
}

$output[$i] =~ /^Message type\s+Dropped/ or die_format_changed($output[$i]);
$i++;
my @stats2;
foreach(; $i < scalar @output; $i++){
    $output[$i] =~ /^(\w+)\s+(\d+)$/ or die_format_changed($output[$i]);
    push(@stats2,
        (
            { ucfirst(lc($1)) . "_Dropped" => $2 }
        )
    );
}

push(@stats2, @stats);

my $msg2;
my $msg3;
my ($thresholds_ok, $thresholds_msg);
foreach(my $i = 0; $i < scalar @stats2; $i++){
    foreach my $stat3 ($stats2[$i]){
        foreach my $key (keys %$stat3){
            $msg2 = "$key=$$stat3{$key} ";
            $msg3 .= "'$key'=$$stat3{$key} ";
            if($key =~ /Pending|Blocked/i){
                ($thresholds_ok, $thresholds_msg) = check_thresholds($$stat3{$key}, 1);
                unless($thresholds_ok){
                    $msg2 = uc $msg2;
                }
            }
            $msg .= $msg2;
        }
    }
}
$msg  =~ s/\s$//;
if($verbose or $status ne "OK"){
    msg_thresholds();
}
$msg .= "| $msg3";

vlog2;
quit $status, $msg;
