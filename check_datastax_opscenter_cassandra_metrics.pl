#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/metrics.html

# The first plugin I started for DataStax OpsCenter in 2013, but the last one to be finished. The idea for this is similar to the Cloudera Manager metrics plugin I wrote while working at Cloudera.

$DESCRIPTION = "Nagios Plugin to fetch and optionally alert on Cassandra cluster metrics via DataStax OpsCenter's Rest API

DataStax OpsCenter has many useful metrics for your Cassandra cluster(s) such as read/write latency and number of operations, both per node as well as aggregated per datacenter. See this link for a list of metric keys to query

http://www.datastax.com/documentation/opscenter/5.0/api/docs/metrics.html#metrics-attribute-key-lists

Some metrics may only apply to Column-Families or Nodes, and will result in UNKNOWN if attempting to querying a combination that doesn't make sense or isn't supported by OpsCenter as OpsCenter will return 'null' in these cases.

Sometimes a metric's latest results will be undefined in OpsCenter. In this case the latest valid metric will be returned instead. Increase --time-period to fetch more historical metrics from the last N minutes so there is more chance of finding a last valid metric to return or specify --latest-only to only return the latest result regardless of whether it's defined or not (in which case you'll get UNKNOWN: 'metric'='undefined').

Tested on DataStax OpsCenter 3.2.2 and 5.0.0";

$VERSION = "0.1";

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

my $dc = "all";
my $cf;
my $device;
# min/max results don't seem to be returned despite API docs saying all 3 are returned by default and trying to fetch min/max results in no results
#my $max;
#my $nodes;
#my $node_group;
#my $node_aggregation;
my $metric;
#my $metrics;
#my $min;
my $period = 1; # last minute
my $latest_only;
#my @metrics;

env_vars(["DATASTAX_OPSCENTER_DATACENTER", "DATACENTER"], \$dc);

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    "m|metric=s"           => [ \$metric,     "Metric(s) to fetch, comma separated. Thresholds may optionally be applied if a single metric is given" ],
    "A|dc|datacenter=s"    => [ \$dc,         "Datacenter. Defaults to 'all' to aggregate metrics across all datacenters for the specified cluster unless a specific --node-ip or --dc is given (\$DATASTAX_OPSCENTER_DATACENTER, \$DATACENTER)" ],
    %keyspaceoption,
    "F|cf|column-family=s" => [ \$cf,         "Column-family to be measured (optional, use with --keyspace for metric drill down)" ],
    %nodeipoption,
    #"nodes=s"             => [ \$nodes,      "Nodes comma separated to fetch metrics for. Optional" ],
    #"node-group=s"        => [ \$node_group, "Node group to fetch metrics for. Optional" ],
    "E|device=s"           => [ \$device,     "Specify a device to fetch a metric for (eg. a specific disk or network interface or 'all' for all disks/network interfaces. Optional, can't be used with --keyspace/--column-family)" ],
    "T|time-period=s"      => [ \$period,      "Time period of last N mins to fetch results for (defaults to 1 for the last minute)" ],
    "L|latest-only"        => [ \$latest_only, "Return latest result even if it's 'undefined'" ],
    #"min"                 => [ \$min,        "Check thresholds against the minimum value returned for the last minute (defautls to comparing to the average)" ],
    #"max"                 => [ \$max,        "Check thresholds against the maximum value returned for the last minute (defaults to comparing to the average)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/cluster metric metrics dc datacenter node-ip nodes node-group keyspace cf column-family device time-period latest-only list-clusters list-keyspaces min max/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
validate_keyspace() if $keyspace;
$dc = validate_alnum($dc, "datacenter") if $dc;
if($cf){
    usage "must specify --keyspace if using --column-family" unless $keyspace;
    $cf     = validate_alnum($cf, "column-family");
}
if($device){
    usage "cannot mix --device with --keyspace / --column-family" if ($keyspace or $cf);
    $device = validate_alnum($device, "device");
}
if($latest_only){
    vlog_option "latest only", "true";
    vlog2 "resetting --time-period to 1 since --latest-only is set" if $period ne 1;
    $period = 1;
}
$period = validate_int($period, "time period (last N minutes)", 1);
#if($metrics){
#    foreach(split(",", $metrics)){
#        $_ = trim($_);
#        /^\s*([\w_-]+)\s*$/ or usage "invalid metric '$_' given, must be alphanumeric, may contain underscores in the middle";
#        push(@metrics, $1);
#    }
#    @metrics or usage "no valid metrics given";
#    @metrics = uniq_array @metrics;
#    vlog_option "metrics", "[ " . join(" ", @metrics) . " ]";
#}
#$metric = $metrics[0];
validate_thresholds();


vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();
list_keyspaces();
list_nodes();

defined($metric) or usage "metric must be specified, see here for list of valid metric keys: http://www.datastax.com/documentation/opscenter/5.0/api/docs/metrics.html#metrics-attribute-key-lists";
$metric =~ /^([\w-]+)$/ or usage "invalid metric given, must be alphanumeric, may contain underscores and dashes";
$metric = $1;

# list network interfaces for node
# "/$cluster/nodes/$node_ip/network_interfaces"
# "/$cluster/nodes/$node_ip/devices"
# "/$cluster/nodes/$node_ip/partitions"

my $url;
sub build_url(){
    if($keyspace){
        $url .= "/$keyspace";
        if($cf){
            $url .= "/$cf";
        }
    }
    if($metric){
        $url .= "/$metric";
        if($device){
            $url .= "/$device";
        }
    }
}
if($node_ip){
    $url = "$cluster/metrics/$node_ip";
    build_url();
} elsif($dc){
    # take an aggregate of the cluster
    $url = "$cluster/cluster-metrics/$dc";
    build_url();
} else {
    # not implementing new-metrics API for now
    usage "must specify --dc or --node-ip to get metrics for";
    # new way of getting all metrics
#    $url = "$cluster/new-metrics?";
#    if($nodes){
#        $url .= "nodes=$nodes";
#    } elsif($node_group){
#        $url .= "node_group=$node_group";
#    } else {
#        $url .= "node_group=all";
#    }
#    if($metric){
#        $url .= "&metrics=$metric";
#    }
#    if($keyspace){
#        $url .= "&keyspace=$keyspace";
#        if($cf){
#            $url .= "&columnfamilies=$cf";
#        }
#    }
#    if($device){
#        $url .= "&devices=$device";
#    }
#    if($node_aggregation){
#        $url .= "&node_aggregation=1";
#    }
}
my $now = time;
$url .= "?start=" . ($now - ($period * 60) ) . "&end=$now";
# retrieve 300 secs before now
# new-metrics is in secs, otherwise in mins - default is in 1 min step
#$url .= "&step=";
#if($new_metrics){
#    $url .= "60";
#} else {
#    $url .= "1";
#}
# return all
#if($min){
#    $url .= "&function=min";
#} elsif($max){
#    $url .= "&function=max";
#}

$json = curl_opscenter $url;
vlog3 Dumper($json);

my @results;
if(isHash($json) and not %{$json}){
    quit "UNKNOWN", "blank metrics returned by DataStax OpsCenter";
} elsif(defined($json->{"Average"})){
    # heap-used / heap-max
    quit "UNKNOWN", "metric not found for this combination" unless defined($json->{"Average"}->{"AVERAGE"});
    @results = get_field_array("Average.AVERAGE");
} elsif(defined($json->{"Total"})){
    # write-ops
    quit "UNKNOWN", "metric not found for this combination" unless defined($json->{"Total"}->{"AVERAGE"});
    @results = get_field_array("Total.AVERAGE");
} elsif(defined($json->{$node_ip})){
    (my $node_ip2 = $node_ip) =~ s/\./\\./g;
    @results = get_field_array("$node_ip2.AVERAGE");
} else {
    quit "UNKNOWN", "neither Average nor Total json child found. $nagios_plugins_support_msg_api";
}
my $metric_result;
my @array;
quit "UNKNOWN", "no results returned" unless @results;
# iterate and take latest non-undef reading since results are in timestamp ascending order
foreach my $array_ref (@results){
    @array = @{$array_ref};
    isArray(\@array) or quit "UNKNOWN", "non-array returned in results. $nagios_plugins_support_msg_api";
    if(scalar @array > 1){
        if(defined($array[1]) and isFloat($array[1])){
            $metric_result = sprintf("%.2f", $array[1]);
        } elsif($latest_only){
            $metric_result = 'undefined';
        }
    }
}
if(defined($metric_result)){
    $msg = "$metric = '$metric_result'";
    check_thresholds($metric_result);
} else {
    unknown;
    $msg = "$metric = 'N/A'";
}
if($node_ip){
    $msg .= " for node '$node_ip'";
} elsif($dc){
    $msg .= " for dc='$dc'";
}
if($keyspace){
    $msg .= " keyspace='$keyspace'";
}
if($cf){
    $msg .= " column-family='$cf'";
}
if($device){
    $msg .= " device='$device'";
}
if(defined($metric_result)){
    $msg .= " | '$metric'=$metric_result";
    msg_perf_thresholds();
}

quit $status, $msg;
