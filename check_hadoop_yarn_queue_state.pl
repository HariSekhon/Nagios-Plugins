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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn queue states via the Resource Manager's REST API

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
$ua->requests_redirectable([]);

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

sub error_handler($) {
        my $response = shift;

        if($response->code eq "307"){
            my $active = $response->header("Location");
            quit("OK", "Standby RM, active at $active");
        }


        unless($response->code eq "200"){
            my $additional_information = "";
            my $json;
            if($json = isJson($response->content)){
                if(defined($json->{"status"})){
                    $additional_information .= ". Status: " . $json->{"status"};
                }
                if(defined($json->{"reason"})){
                    $additional_information .= ". Reason: " . $json->{"reason"};
                } elsif(defined($json->{"message"})){
                    $additional_information .= ". Message: " . $json->{"message"};
                }
            }
            quit("CRITICAL", $response->code . " " . $response->message . $additional_information);
        }
        unless($response->content){
            quit("CRITICAL", "blank content returned from '" . $response->request->uri . "'");
        }
}

my $content = curl $url, undef, undef, undef, \&error_handler;


#my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    if ($content =~ /This is standby RM./) { quit $status, $content; }

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
