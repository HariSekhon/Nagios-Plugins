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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn queue capacity used % via the Resource Manager's REST API

Optional thresholds may be applied but this is not recommended as queues may intermittently allocate all resources, this is more useful for monitoring with graphing and capacity planning since it outputs perfdata.

This supports the Capacity Scheduler and will not work for the Fifo Scheduler due to the API exposing different information. It has also not been tested on the Fair Scheduler.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0), HDP 2.6 (Hadoop 2.7.3) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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

my $queue;
my $list_queues;
my $absolute;

%options = (
    %hostoptions,
    "Q|queue=s"      =>  [ \$queue,         "Queue to check (defaults to checking all queues)" ],
    "T|total"        =>  [ \$absolute,      "Checks % used of total cluster capacity (default for Fair Scheduler, for Capacity Scheduler checks queue's % used of queue's own configured capacity unless this is specified)" ],
    "list-queues"    =>  [ \$list_queues,   "List all queues" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/queue total list-queues/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster/scheduler";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my %scheduler_info = get_field_hash("scheduler.schedulerInfo");
my @queues;
my $fair_scheduler = 0;
if(defined($scheduler_info{"rootQueue"})){
    $fair_scheduler = 1;
    $absolute = 1;
    @queues = get_field2_array(\%scheduler_info, "rootQueue.childQueues.queue")
} else {
    @queues = get_field2_array(\%scheduler_info, "queues.queue");
}
$msg = "queue used capacity of " . ($absolute ? "total cluster" : "allocated" ) . ": ";

if($list_queues){
    foreach my $q (@queues){
        print get_field2($q, "queueName") . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $found;
my $msg2;
my $used_pc = "usedCapacity";
$used_pc = "absoluteUsedCapacity" if $absolute;

sub check_queue($){
    my $q = shift;
    my $name = get_field2($q, "queueName");
    if($queue){
        $queue eq $name or return;
        $found = 1;
    }
    my $used_capacity;
    if($fair_scheduler){
        my $used_memory = sprintf("%.2f", get_field2_float($q, "usedResources.memory"));
        my $cluster_memory = sprintf("%.2f", get_field2_float($q, "clusterResources.memory"));
        $used_capacity = sprintf("%.2f", $used_memory / $cluster_memory * 100);
    } else {
        $used_capacity = sprintf("%.2f", get_field2_float($q, $used_pc));
    }
    $msg .= sprintf("'%s' = %s%%", $name, $used_capacity);
    check_thresholds($used_capacity);
    $msg .= ", ";
    $msg2 .= sprintf("'%s'=%s%%", $name, $used_capacity);
    $msg2 .= msg_perf_thresholds(1);
    $msg2 .= " ";
}

foreach my $q (@queues){
    check_queue($q);
    my $q2;
    if(defined($q->{"queues"}) and $q2 = get_field2_array($q, "queues")){
        check_queue($q2);
    }
}
if($queue){
    $found or quit "UNKNOWN", "queue '$queue' not found, check you specified the right queue name using --list-queues. If you're sure you've specified the right queue name then $nagios_plugins_support_msg_api";
}
$msg =~ s/, $//;
$msg .= " | $msg2";

quit $status, $msg;
