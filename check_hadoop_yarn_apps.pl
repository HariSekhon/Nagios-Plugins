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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn Apps via Resource Manager jmx

Optional thresholds on running yarn apps to aid in capacity planning

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

$VERSION = "0.3";

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

my $queue = "root";

%options = (
    %hostoptions,
    "Q|queue=s"      =>  [ \$queue, "Queue to output stats for (default: root)" ],
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0 });

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
my $apps_submitted = 0;
my $apps_running   = 0;
my $apps_pending   = 0;
my $apps_completed = 0;
my $apps_killed    = 0;
my $apps_failed    = 0;
my $active_users   = 0;
my $active_apps    = 0;

my $mbean_name = "Hadoop:service=ResourceManager,name=QueueMetrics";
$mbean_name .= ",q0=$queue";
foreach(@beans){
    vlog2 Dumper($_) if get_field2($_, "name") =~ /QueueMetrics/;
    next unless get_field2($_, "name") =~ /^$mbean_name$/;
    $found_mbean++;
    $apps_submitted = get_field2_int($_, "AppsSubmitted");
    $apps_running   = get_field2_int($_, "AppsRunning");
    $apps_pending   = get_field2_int($_, "AppsPending");
    $apps_completed = get_field2_int($_, "AppsCompleted");
    $apps_killed    = get_field2_int($_, "AppsKilled");
    $apps_failed    = get_field2_int($_, "AppsFailed");
    $active_users   = get_field2_int($_, "ActiveUsers");
    $active_apps    = get_field2_int($_, "ActiveApplications");
    last;
}
$msg  = "yarn apps for queue '$queue': ";
$msg .= "$apps_running running";
check_thresholds($apps_running);
$msg .= ", ";
$msg .= "$apps_pending pending, ";
$msg .= "$active_apps active, ";
$msg .= "$apps_submitted submitted, ";
$msg .= "$apps_completed completed, ";
$msg .= "$apps_killed killed, ";
$msg .= "$apps_failed failed. ";
$msg .= "$active_users active users";
$msg .= " | ";
$msg .= "'apps running'=$apps_running";
msg_perf_thresholds();
$msg .= " ";
$msg .= "'apps pending'=$apps_pending ";
$msg .= "'apps active'=$active_apps ";
$msg .= "'apps submitted'=${apps_submitted}c ";
$msg .= "'apps completed'=${apps_completed}c ";
$msg .= "'apps killed'=${apps_killed}c ";
$msg .= "'apps failed'=${apps_failed}c ";
$msg .= "'active users'=$active_users";

quit "UNKNOWN", "failed to find mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
