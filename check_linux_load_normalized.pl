#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-28 20:32:45 +0100 (Mon, 28 Apr 2014)
#  2012 originally?
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Linux system load normalized / averaged against the number of CPU cores to give a more accurate impression of how CPU bound the entire server is across all CPUs/cores

Makes it easy to check load across all servers with the same check since it calculates and takes in to account CPU core count differences across servers

Generally you should be concerned if the average normalized load across all cores is approaching 1 for a server which means that all it's CPU cores are busy";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

set_threshold_defaults(0.7, 1);

my $load;
my $cpu_perf;

%options = (
    "C|cpu-cores-perfdata" => [ \$cpu_perf, "Output CPU Cores in perfdata" ],
    %thresholdoptions,
);
@usage_order = qw/cpu-cores-perfdata warning critical/;

get_options();

validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 0 } );

linux_only();

vlog2;
set_timeout();

$status = "OK";

my $proc_load = "/proc/loadavg";
my $fh = open_file $proc_load;
while(<$fh>){
    chomp $_;
    vlog3 $_;
    if(/(\d+(?:\.\d+))\s/){
        $load = $1;
        last;
    }
}
vlog2;
defined($load) or quit "UNKNOWN", "failed to determine load from $proc_load. $nagios_plugins_support_msg";

my $cpuinfo = open_file "/proc/cpuinfo";
my $cpu_cores = 0;
while(<$cpuinfo>){
    chomp $_;
    vlog3 $_;
    /^processor\s+:\s+\d+/ and $cpu_cores++;
}
vlog2;
$cpu_cores > 0 or quit "UNKNOWN", "failed to find CPU core count from /proc/cpuinfo. $nagios_plugins_support_msg";
plural $cpu_cores;
vlog2 "found $cpu_cores CPU core$plural";

my $load_averaged = $load / ($cpu_cores + 0.0);
vlog2 "load          = $load";
vlog2 "load averaged = $load_averaged ( load / cpu_cores )";

$load_averaged = sprintf("%.2f", $load_averaged);
$msg .= "average load by CPU = $load_averaged";
check_thresholds($load_averaged);
$msg .= ", load = $load / CPU cores = $cpu_cores";
$msg .= " | averaged_load=$load_averaged";
msg_perf_thresholds();
$msg .= " load=$load";
$msg .= " 'CPU cores'=$cpu_cores" if $cpu_perf;

vlog2;
quit $status, $msg;
