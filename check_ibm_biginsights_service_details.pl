#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_cluster_mgt.html?lang=en

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Service Details via BigInsights Console REST API

Supported Services:

mr_summary        - checks MapReduce service for runing state and dead JobTrackers
mr_tasktrackers   - checks MapReduce service for dead TaskTrackers
fs_summary        - checks HDFS service for running state and dead NameNodes
fs_datanodes      - checks HDFS service for dead DataNodes
hive              - checks Hive service for running state, HiveServers2 and HWI running
catalog           - checks BigInsights Application Catalog service for running state
hbase_summary     - checks HBase service for running state and dead HBase Masters
hbase_servers     - checks HBase service for dead HBase Region Servers
zookeeper_servers - checks ZooKeeper service for dead ZooKeeper servers

Tested on IBM BigInsights Console 2.1.2.0";

our $VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(0, 0);

# TODO: jaql, flume_summary and flume_servers
my @valid_services = qw/
mr_summary
mr_tasktrackers
fs_summary
fs_datanodes
hive
jaql
catalog
hbase_summary
hbase_servers
zookeeper_servers
flume_summary
flume_servers
/;

my $service;
my $list_services = 0;

%options = (
    %biginsights_options,
    "s|service=s"       =>  [ \$service,        "Check state of a given service. See --help header description for list of supported service names" ],
    %thresholdoptions,
);
splice @usage_order, 4, 0, "service";

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
defined($service) or usage "service not defined";
grep { $service eq $_ } @valid_services or usage "invalid service given, must be one of: " . join(", ", @valid_services);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1 });
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $now = time;

curl_biginsights "/ClusterStatus/$service.json", $user, $password;

# These shown in docs don't appear for HBase:
#
# usedHeap / maxHeap
# number_of_regions

my $running;
my %not_started;
my %not_running;
my $node;
my $ss;
my $node_count;
my $not_running_count;
my $not_started_count;

sub check_running(){
    $running = get_field("running");
    critical unless $running;
    $running = ( $running ? "yes" : "NO" );
}

sub check_ss_running(){
    if($ss ne "Running"){
        $not_running{$node} = $ss;
    } elsif(not $running){
        $not_running{$node} = "";
    }
}

sub count_nodes(){
    $node_count        = scalar(@{$json->{"items"}});
    $not_running_count = scalar(keys %not_running);
    $not_started_count = scalar(keys %not_started);

}

sub msg_nodes(){
    if($verbose){
        if(%not_running){
            $msg .= ". Not running: " . join(", ", sort keys %not_running);
        }
        if(%not_started){
            $msg .= ". Not in started state: ";
            foreach(sort keys %not_started){
                $msg .= sprintf("%s[%s], ", $_, $not_started{$_});
            }
            $msg =~ s/, $//;
        }
    }
}

sub msg_not_running_nodes(){
    if($verbose){
        if(%not_running){
            $msg .= ". Not running: ";
            foreach(sort keys %not_running){
                $msg .= sprintf("%s", $_);
                $msg .= sprintf("[%s]", $not_running{$_}) if $not_running{$_};
                $msg .= ", ";
            }
            $msg =~ s/, $//;
        }
    }
}

$msg .= "BigInsights ";
if($service eq "mr_summary"){
    $msg .= "'" . get_field("label") . "' service";
    check_running();
    $msg .= " running = $running"
          . ", dead JobTrackers = " . get_field("deadJTs");
    check_thresholds(get_field("deadJTs"));
    $msg .= ", live JobTrackers = " . get_field("liveJTs")
          . ", live daemons = "     . get_field("live")
          . ", dead daemons = "     . get_field("dead")
          . " |"
          . " 'dead JobTrackers'=" . get_field("deadJTs")
          . msg_perf_thresholds(1)
          . " 'live JobTrackers'=" . get_field("liveJTs")
          . " 'live daemons'="     . get_field("live")
          . " 'dead daemons'="     . get_field("dead");
} elsif($service eq "mr_tasktrackers"){
    isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array. $nagios_plugins_support_msg_api";
    # XXX: could check ts field for check lag but getting a bit cluttered
    foreach my $tasktracker (@{$json->{"items"}}){
        $node    = get_field2($tasktracker, "tasktracker");
        $ss      = get_field2($tasktracker, "ss");
        $running = get_field2($tasktracker, "running");
        $ss eq "Started" or $not_started{$node} = $ss;
        $running or $not_running{$node} = $running;
    }
    count_nodes();
    $msg .= sprintf("MapReduce service %d TaskTracker%s, %d not running", $node_count, plural($node_count), $not_running_count);
    check_thresholds(scalar(keys %not_running));
    $msg .= sprintf(", %d not in started state", $not_started_count);
    msg_nodes();
    $msg .= sprintf(" | tasktrackers=%d 'tasktrackers not running'=%d 'tasktrackers not started'=%d", $node_count, $not_running_count, $not_started_count);
} elsif($service eq "fs_summary"){
    $msg .= "'" . get_field("label") . "' service";
    check_running();
    $msg .= " running = $running"
          . ", dead NameNodes = " . get_field("deadNNs");
    check_thresholds(get_field("deadNNs"));
    $msg .= ", live NameNodes = " . get_field("liveNNs")
          . ", live daemons = "   . get_field("live")
          . ", dead daemons = "   . get_field("dead")
          . ", ha = " . ( get_field("qjm") ? "yes" : "no" )
          . ", qjm = " . ( get_field("qjm") ? "yes" : "no" )
          . " |"
          . " 'dead NameNodes'=" . get_field("deadNNs")
          . msg_perf_thresholds(1)
          . " 'live NameNodes'=" . get_field("liveNNs")
          . " 'live daemons'="   . get_field("live")
          . " 'dead daemons'="   . get_field("dead");
} elsif($service eq "fs_datanodes"){
    isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array. $nagios_plugins_support_msg_api";
    # XXX: could check ts field for check lag but genodeing a bit clunodeered
    foreach my $datanode (@{$json->{"items"}}){
        $node    = get_field2($datanode, "hostname");
        $ss      = get_field2($datanode, "ss");
        $running = get_field2($datanode, "running");
        check_ss_running();
    }
    count_nodes();
    $msg .= sprintf("HDFS service %d DataNode%s, %d not running", $node_count, plural($node_count), $not_running_count);
    check_thresholds(scalar(keys %not_running));
    msg_not_running_nodes();
    $msg .= sprintf(" | datanodes=%d 'datanodes not running'=%d", $node_count, $not_running_count);
    msg_perf_thresholds();
} elsif($service eq "hive"){
    $msg .= "'" . get_field("label") . "' service ";
    check_running();
    my $hwi_running         = get_field("hwiRunning");
    my $hiveserver2_running = get_field("nodeRunning");
    $hwi_running         or critical;
    $hiveserver2_running or critical;
    $hwi_running         = ( $running ? "yes" : "NO" );
    $hiveserver2_running = ( $running ? "yes" : "NO" );
    $msg .= "running = $running, hiveserver2 running = $hiveserver2_running, hwi running = $hwi_running";
} elsif($service eq "jaql"){
    # TODO: got 404, "JAQL Server is not yet deployed" in html but not returned by curl, need a curl override
    quit "UNKNOWN", "Jaql service is not supported yet. $nagios_plugins_support_msg_api";
} elsif($service eq "catalog"){
    $running = get_field("running");
    critical unless $running;
    $msg .= "Application Catalog service running = " . ( $running ? "yes" : "NO" );
} elsif($service eq "hbase_summary"){
    $msg .= "'" . get_field("label") . "' service";
    check_running();
    $msg .= " running = $running"
          . ", dead HBase Masters = " . get_field("deadMasters");
    check_thresholds(get_field("deadMasters"));
    $msg .= ", live HBase Masters = " . get_field("liveMasters")
          . ", live daemons = "     . get_field("live")
          . ", dead daemons = "     . get_field("dead")
          . " |"
          . " 'dead HBase Masters'=" . get_field("deadMasters")
          . msg_perf_thresholds(1)
          . " 'live HBase Masters'=" . get_field("liveMasters")
          . " 'live daemons'="     . get_field("live")
          . " 'dead daemons'="     . get_field("dead");
} elsif($service eq "hbase_servers"){
    isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array. $nagios_plugins_support_msg_api";
    # XXX: could check ts field for check lag but getting a bit cluttered
    foreach my $hbase_server (@{$json->{"items"}}){
        $node      = get_field2($hbase_server, "url");
        $ss      = get_field2($hbase_server, "ss");
        $running = get_field2($hbase_server, "running");
        check_ss_running();
    }
    count_nodes();
    $msg .= sprintf("HBase service %d region server%s, %d not running", $node_count, plural($node_count), $not_running_count);
    check_thresholds(scalar(keys %not_running));
    #$msg .= sprintf(", %d not in started state", $not_started_count);
    msg_not_running_nodes();
    $msg .= sprintf(" | 'hbase servers'=%d 'hbase servers not running'=%d 'hbase servers not started'=%d", $node_count, $not_running_count, $not_started_count);
} elsif($service eq "zookeeper_servers"){
    isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array. $nagios_plugins_support_msg_api";
    # XXX: could check ts field for check lag but getting a bit cluttered
    foreach my $zookeeper_server (@{$json->{"items"}}){
        $node      = get_field2($zookeeper_server, "url");
        $running = get_field2($zookeeper_server, "running");
        $running or $not_running{$node} = $running;
    }
    count_nodes();
    $msg .= sprintf("ZooKeeper service %d server%s, %d not running", $node_count, plural($node_count), $not_running_count);
    check_thresholds(scalar(keys %not_running));
    msg_nodes();
    $msg .= sprintf(" | 'zookeeper servers'=%d 'zookeeper servers not running'=%d", $node_count, $not_running_count);
} else {
    code_error "unsupported service, caught late, should have been caught at option parsing time";
}

quit $status, $msg;
