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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn queue states via the Resource Manager's REST API

This supports the Capacity Scheduler and will not work for the Fifo Scheduler due to the API exposing different information. It has also not been tested on the Fair Scheduler.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0), HDP 2.6 (Hadoop 2.7.3) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Yarn Resource Manager");

my $queue;
my $list_queues;

%options = (
    %hostoptions,
    "Q|queue=s"      =>  [ \$queue,         "Queue to check (defaults to checking all queues)" ],
    "list-queues"    =>  [ \$list_queues,   "List all queues" ],
);
splice @usage_order, 6, 0, qw/queue list-queues/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);

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

$msg = "queue state: ";
my @queues = get_field_array("scheduler.schedulerInfo.queues.queue");

if($list_queues){
    foreach my $q (@queues){
        print get_field2($q, "queueName") . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

sub check_queue_state($){
    my $state = shift;
    if($state eq "RUNNING"){
        # ok
        return "running";
    } else {
        critical;
        return $state;
    }
}

my $found;
sub check_queue($){
    my $q = shift;
    my $name = get_field2($q, "queueName");
    if($queue){
        $queue eq $name or return;
        $found = 1;
    }
    $msg .= sprintf("'%s' = %s, ", $name, check_queue_state( get_field2($q, "state") ) );
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

quit $status, $msg;
