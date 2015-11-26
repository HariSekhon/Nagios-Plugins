#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-16 21:00:43 +0100 (Tue, 16 Sep 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/cluster_info.html

$DESCRIPTION = "Nagios Plugin to check Cassandra nodes last seen time lag via DataStax OpsCenter Rest API

The last seen time is compared to the warning/critical thresholds in seconds.

Use --node-ip to check a specific node only.

Issues: I've had issues with this on 5.0.0 where DataStax OpsCenter reports 0 last seen time lag if it hasn't seen a node since DataStax OpsCenter or the DataStax OpsCenter Agent are restarted while a node is down or if the DataStax OpsCenter Agent is stopped and Cassandra later goes down. There isn't another field I can see that differentiates this from the 0 last seen time that connected nodes have :-/ This seems to work normally with DataStax OpsCenter + Agent 3.2.2.

See also check_cassandra_nodes.pl for a robust Cassandra view of nodes

Tested on DataStax OpsCenter 3.2.2 and 5.0.0";

$VERSION = "0.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use Data::Dumper;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(10, 60);

my $show_fqdn;

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    %nodeipoption,
    "show-fqdn" => [ \$show_fqdn, "Display FQDNs instead of just short hostnames" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/cluster node-ip show-fqdn list-clusters/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
$node_ip = validate_ip($node_ip) if $node_ip;
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

my $url = "$cluster/nodes";
$url .= "/$node_ip" if $node_ip;

$json = curl_opscenter $url;
vlog3 Dumper($json);

if($node_ip){
} else {
    $msg = "nodes last seen secs ago: ";
}
my $msg2;
my %nodes;
my $highest_lag = 0;
my $failing_nodes = 0;
sub check_node($){
    my $hashref = shift;
    my $node_ip2  = get_field2($hashref, "node_ip");
    my $last_seen = get_field2_int($hashref, "last_seen");
    $last_seen = time - $last_seen if $last_seen != 0;
    if($last_seen < 0){
        quit "UNKNOWN", "last seen is less than 0, server clocks must be out of sync!!";
    }
    # not good enough at catching the node last seen
    #if($last_seen == 0 and not defined($hashref->{"mode"})){
    #    quit "UNKNOWN", "mode couldn't be determined but last seen was reported as 0 which means that DataStax OpsCenter hasn't seen the node"
    #}
    # get_field2 returns field not found if val is undef, fix this
    #my $node_name = get_field2($hashref, "node_name");
    my $node_name = "";
    if(defined($hashref->{"node_name"})){
        $node_name = $hashref->{"node_name"};
        unless($show_fqdn){
            $node_name =~ s/([^\.])\..*$/$1/;
        }
    } else {
        $node_name = $node_ip2;
    }
    $highest_lag = $last_seen if $last_seen > $highest_lag;
    if($node_ip){
        $msg  = "node $node_name";
        $msg .= "[$node_ip2]" if ($verbose and $node_name ne $node_ip2);
        $msg .= " last seen $last_seen secs ago";
    } else {
        $msg .= "$node_name";
        $msg .= "[$node_ip2]" if($verbose and $node_name ne $node_ip2);
        $msg .= "=$last_seen";
    }
    $msg .= ", ";
    $node_name =~ s/'//g;
    $msg2 .= "'node $node_name last seen secs ago'=${last_seen}s" . msg_perf_thresholds(1) . " ";
}

if($node_ip){
    if(defined($json->{"node_ip"})){
        $json->{"node_ip"} eq $node_ip or quit "UNKNOWN", "node_ip returned does not match the one specified!!! $nagios_plugins_support_msg_api";
        check_node($json);
    } else {
        quit "UNKNOWN", "node '$node_ip' not found";
    }
} else {
    isArray($json) or quit "UNKNOWN", "non-array returned by DataStax OpsCenter. $nagios_plugins_support_msg_api";
    @{$json} or quit "CRITICAL", "no nodes returned by DataStax OpsCenter. Has OpsCenter been recently restarted without nodes being up?";
    foreach my $hashref (@{$json}){
        check_node($hashref);
    }
}
$msg =~ s/, $//;
check_thresholds($highest_lag);
$msg .= " in cluster '$cluster'" if $verbose;
$msg .= " | $msg2";

vlog2;
quit $status, $msg;
