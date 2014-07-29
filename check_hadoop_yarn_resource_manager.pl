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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn Resource Manager Apps and App Memory available via jmx

Optional thresholds on available App Memory to aid in capacity planning

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

$VERSION = "0.2";

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

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Yarn Resource Manager");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "lower", "positive" => 1, "integer" => 0 });

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
foreach(@beans){
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
    check_thresholds($available_mb);
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
    msg_perf_thresholds();
    last;
}

quit "UNKNOWN", "failed to find mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
