#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-15 04:56:49 +0100 (Tue, 15 Oct 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to fetch Cassandra's netstats per node by parsing 'nodetool netstats'.

Checks Pending commands and responses against warning/critical thresholds.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Written and tested against Cassandra 2.0.1 and 2.0.9, DataStax Community Edition";

$VERSION = "0.6.3";

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
while($i < scalar @output and $output[$i] !~ /Pool\s+Name\s+Active\s+Pending\s+Completed\s*$/i){
    $i++;
}
$i++;
my %stats;
foreach(; $i < scalar @output; $i++){
    $output[$i] =~ /^\s*$/ and $i++ and last;
    $output[$i] =~ /^(\w+)\s+(n\/a|\d+)\s+(\d+)\s+(\d+)\s*$/ or die_nodetool_unrecognized_output($output[$i]);
    $stats{$1}{"Active"}    = ( $2 eq "n/a" ? 0 : $2 );
    $stats{$1}{"Pending"}   = $3;
    $stats{$1}{"Completed"} = $4;
}

my $msg2;
my $msg3;
my ($thresholds_ok, $thresholds_msg);
foreach my $type (qw/Commands Responses/){
    defined($stats{$type}) or quit "'$type' not found in netstats output. $nagios_plugins_support_msg";
    foreach my $type2 (qw/Active Pending Completed/){
        defined($stats{$type}{$type2}) or quit "'$type' => '$type2' not found in netstats output. $nagios_plugins_support_msg";
        $msg2 = "${type}_$type2=$stats{$type}{$type2}";
        $msg3 .= $msg2;
        $msg2 .= " ";
        if($type2 eq "Pending"){
            ($thresholds_ok, $thresholds_msg) = check_thresholds($stats{$type}{$type2}, 1);
            unless($thresholds_ok){
                $msg2 = uc $msg2;
            }
            $msg3 .= msg_perf_thresholds(1);
        } elsif($type2 eq "Completed"){
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
$msg .= " | $msg3";

vlog2;
quit $status, $msg;
