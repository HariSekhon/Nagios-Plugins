#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn queue for pending Apps via Resource Manager JMX API

Checks a given queue, 'default' if not specified. Can also list queues for convenience.

Optional thresholds on pending yarn apps in queue to aid in capacity planning, or alternatively running yarn apps in queue if using --running switch

Also displays active users in a queue, be aware however active users are only counted in leaf queues as of Hadoop 2.4.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) with Capacity Scheduler queues and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.6";

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

my $queue = "default";
my $running;
my $list_queues;

%options = (
    %hostoptions,
    "Q|queue=s"      =>  [ \$queue,         "Queue to output stats for, prefixed with root queue which may be optionally omitted (default: root.default)" ],
    "r|running"      =>  [ \$running,       "Checking running instead of pending apps against thresholds" ],
    "list-queues"    =>  [ \$list_queues,   "List all queues" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/queue running list-queues/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0 });

vlog2;
set_timeout();

$status = "OK";

#my $url = "http://$host:$port/jmx?qry=Hadoop:service=ResourceManager,name=QueueMetrics*";
my $url = "http://$host:$port/jmx?qry=Hadoop:*";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
#vlog3(Dumper($json));

my @beans = get_field_array("beans");

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

my $mbean_queuemetrics = "Hadoop:service=ResourceManager,name=QueueMetrics";
my $mbean_name = "$mbean_queuemetrics";
$queue =~ /^root(?:\.|$)/ or $queue = "root.$queue";
my $i=0;
foreach(split(/\./, $queue)){
    $mbean_name .= ",q$i=$_";
    $i++;
}
$queue =~ s/^root\.//;
vlog2 "searching for mbean $mbean_name" unless $list_queues;
my @queues;
my $found_queue = 0;
foreach(@beans){
    vlog2 Dumper($_) if get_field2($_, "name") =~ /QueueMetrics/;
    my $this_mbean_name = get_field2($_, "name");
    if($this_mbean_name =~ /^$mbean_queuemetrics,q0=(.*)$/){
        my $q_name = $1;
        $q_name =~ s/,q\d+=/./;
        push(@queues, $q_name);
    }
    next unless $this_mbean_name =~ /^$mbean_name$/;
    $found_queue++;
    $apps_submitted = get_field2_int($_, "AppsSubmitted");
    $apps_running   = get_field2_int($_, "AppsRunning");
    $apps_pending   = get_field2_int($_, "AppsPending");
    $apps_completed = get_field2_int($_, "AppsCompleted");
    $apps_killed    = get_field2_int($_, "AppsKilled");
    $apps_failed    = get_field2_int($_, "AppsFailed");
    $active_users   = get_field2_int($_, "ActiveUsers");
    $active_apps    = get_field2_int($_, "ActiveApplications");
}
if($list_queues){
    print "Queues:\n\n";
    foreach(@queues){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}
quit "UNKNOWN", "failed to find mbean for queue '$queue'. Did you specify the correct queue name? See --list-queues for valid queue names. If you're sure you've specified the right queue name then $nagios_plugins_support_msg_api" unless $found_queue;
quit "UNKNOWN", "duplicate mbeans found for queue '$queue'! $nagios_plugins_support_msg_api" if $found_queue > 1;

$msg  = "yarn app stats for queue '$queue': ";
$msg .= "$apps_running running";
check_thresholds($apps_running) if $running;
$msg .= ", ";
$msg .= "$apps_pending pending";
check_thresholds($apps_pending) unless $running;
$msg .= ", ";
$msg .= "$active_apps active, ";
$msg .= "$apps_submitted submitted, ";
$msg .= "$apps_completed completed, ";
$msg .= "$apps_killed killed, ";
$msg .= "$apps_failed failed. ";
plural $active_users;
$msg .= "$active_users active user$plural";
$msg .= " | ";
$msg .= "'apps running'=$apps_running";
msg_perf_thresholds() if $running;
$msg .= " ";
$msg .= "'apps pending'=$apps_pending";
msg_perf_thresholds() unless $running;
$msg .= " ";
$msg .= "'apps active'=$active_apps ";
$msg .= "'apps submitted'=${apps_submitted}c ";
$msg .= "'apps completed'=${apps_completed}c ";
$msg .= "'apps killed'=${apps_killed}c ";
$msg .= "'apps failed'=${apps_failed}c ";
$msg .= "'active users'=$active_users";

quit $status, $msg;
