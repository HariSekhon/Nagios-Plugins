#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn Resource Manager

Checks:

- Node Manager metrics and perf data, thresholds on unhealthy node managers
- Yarn App stats (running, pending, active, submitted, completed, killed, failed)
- Heap Used % vs thresholds
- Non-Heap Used % vs thresholds

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8088);
#set_threshold_defaults(80, 90);

env_creds("Yarn Resource Manager");

my $heap          = 0;
my $non_heap      = 0;
my $node_managers = 0;
my $app_stats     = 0;

%options = (
    %hostoptions,
    "node-managers"     => [ \$node_managers,   "Node Manager metrics, check unhealthy node managers against thresholds" ],
    "app-stats"         => [ \$app_stats,       "Yarn App stats (running, pending, active, submitted, completed, killed, failed)" ],
    "heap-used"         => [ \$heap,            "Check heap memory used % against thresholds" ],
    "non-heap-used"     => [ \$non_heap,        "Check non-heap memory used % against thresholds" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/node-managers app-stats heap-used non-heap-used/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
if($heap + $non_heap + $node_managers + $app_stats != 1){
    usage "must specify exactly one of --node-managers / --app-stats / --heap-used / --non-heap-used";
}
if($heap or $non_heap or $node_managers){
    validate_thresholds(1, 1, { "positive" => 1, "simple" => "upper" });
} else {
    validate_thresholds(undef, undef, { "positive" => 1});
}

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my @beans = get_field_array("beans");

isArray($beans[0]) or quit "UNKNOWN", "mbean array index 0 is not an array as expected. $nagios_plugins_support_msg_api";
my $found_mbean = 0;

# Other MBeans of interest:
#
#       Hadoop:service=ResourceManager,name=RpcActivityForPort8025 (RPC)
#       Hadoop:service=ResourceManager,name=RpcActivityForPort8050 (RPC)
#       java.lang:type=MemoryPool,name=Code Cache
#       java.lang:type=Threading
#       Hadoop:service=ResourceManager,name=RpcActivityForPort8141
#       Hadoop:service=ResourceManager,name=RpcActivityForPort8030
#       Hadoop:service=ResourceManager,name=JvmMetrics
if($heap or $non_heap){
    foreach(@{$beans[0]}){
        next unless get_field2($_, "name") eq "java.lang:type=Memory";
        $found_mbean++;
        if($heap){
            my $heap_max     = get_field2_int($_, "HeapMemoryUsage.max");
            my $heap_used    = get_field2_int($_, "HeapMemoryUsage.used");
            my $heap_used_pc = sprintf("%.2f", $heap_used / $heap_max * 100);

            $msg = sprintf("%s%% heap used (%s/%s)", $heap_used_pc, human_units($heap_used), human_units($heap_max));
            check_thresholds($heap_used_pc);
            $msg .= sprintf(" | 'heap used %%'=%s%%", $heap_used_pc);
            msg_perf_thresholds();
            $msg .= sprintf(" 'heap used'=%sb 'heap max'=%sb", $heap_used, $heap_max);
        } elsif($non_heap){
            my $non_heap_max     = get_field2_int($beans[0][0], "NonHeapMemoryUsage.max");
            my $non_heap_used    = get_field2_int($beans[0][0], "NonHeapMemoryUsage.used");
            my $non_heap_used_pc = sprintf("%.2f", $non_heap_used / $non_heap_max * 100);

            $msg = sprintf("%s%% non-heap used (%s/%s)", $non_heap_used_pc, human_units($non_heap_used), human_units($non_heap_max));
            check_thresholds($non_heap_used_pc);
            $msg .= sprintf(" | 'non-heap used %%'=%s%%", $non_heap_used_pc);
            msg_perf_thresholds();
            $msg .= sprintf(" 'non-heap used'=%sb 'non-heap max'=%sb", $non_heap_used, $non_heap_max);
        } else {
            code_error "error determining heap / non_heap";
        }
    }
} elsif($node_managers){
    foreach(@{$beans[0]}){
        next unless get_field2($_, "name") eq "Hadoop:service=ResourceManager,name=ClusterMetrics";
        $found_mbean++;
        my $active_NMs    = get_field2_int($_, "NumActiveNMs");
        my $decomm_NMs    = get_field2_int($_, "NumDecommissionedNMs");
        my $lost_NMs      = get_field2_int($_, "NumLostNMs");
        my $unhealthy_NMs = get_field2_int($_, "NumUnhealthyNMs");
        my $rebooted_NMs  = get_field2_int($_, "NumUnhealthyNMs");
        $msg = "node managers: $active_NMs active, $decomm_NMs decommissioned, $lost_NMs lost, $unhealthy_NMs unhealthy";
        check_thresholds($unhealthy_NMs);
        $msg .= ", $rebooted_NMs rebooted";
        $msg .= sprintf(" | 'active node managers'=%d 'decommissioned node managers'=%d 'lost node managers'=%d 'unhealthy node managers'=%d", $active_NMs, $decomm_NMs, $lost_NMs, $unhealthy_NMs);
        msg_perf_thresholds();
        $msg .= sprintf(" 'rebooted node managers'=%d", $unhealthy_NMs);
    }
} elsif($app_stats){
    foreach(@{$beans[0]}){
        next unless get_field2($_, "name") eq "Hadoop:service=ResourceManager,name=QueueMetrics,q0=root";
        $found_mbean++;
        my $apps_submitted = get_field2_int($_, "AppsSubmitted");
        my $apps_running   = get_field2_int($_, "AppsRunning");
        my $apps_pending   = get_field2_int($_, "AppsPending");
        my $apps_completed = get_field2_int($_, "AppsCompleted");
        my $apps_killed    = get_field2_int($_, "AppsKilled");
        my $apps_failed    = get_field2_int($_, "AppsFailed");
        my $available_mb   = get_field2_float($_, "AvailableMB");
        my $active_users   = get_field2_int($_, "ActiveUsers");
        my $active_apps    = get_field2_int($_, "ActiveApplications");
        $msg  = "yarn apps: ";
        $msg .= "$apps_running running, ";
        $msg .= "$apps_pending pending, ";
        $msg .= "$active_apps active, ";
        $msg .= "$apps_submitted submitted, ";
        $msg .= "$apps_completed completed, ";
        $msg .= "$apps_killed killed, ";
        $msg .= "$apps_failed failed. ";
        $msg .= "$active_users active users, ";
        $msg .= "$available_mb available mb";
        $msg .= " | ";
        $msg .= "'apps running'=$apps_running ";
        $msg .= "'apps pending'=$apps_pending ";
        $msg .= "'apps active'=$active_apps ";
        $msg .= "'apps submitted'=$apps_submitted ";
        $msg .= "'apps completed'=$apps_completed ";
        $msg .= "'apps killed'=$apps_killed ";
        $msg .= "'apps failed'=$apps_failed ";
        $msg .= "'active users'=$active_users ";
        $msg .= "'available mb'=${available_mb}MB";
    }
} else {
    code_error "no test specified, caught-late";
}

if($found_mbean == 0){
    quit "UNKNOWN", "failed to find mbean. $nagios_plugins_support_msg_api";
} elsif($found_mbean == 1){
    # expected
} elsif($found_mbean > 1){
    quit "UNKNOWN", "more than one matching mbean found! $nagios_plugins_support_msg_api";
} else {
    code_error "mbean logic needs checking";
}

quit $status, $msg;
