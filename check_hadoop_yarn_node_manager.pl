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

$DESCRIPTION = "Nagios Plugin to check the state of a given Hadoop Yarn Node Manager via the Node Manager's REST API

Checks the given Node Manager 'nodeHealthy' field is true and reports the healthReport status.

Thresholds apply to lag time in seconds for last node report.

See also:

- check_hadoop_yarn_node_manager_via_rm.pl (from Resource Manager's perspective, has more info and can also list node managers)
- check_hadoop_yarn_node_managers.pl (aggregate view of the number of healthy / unhealthy Node Managers)

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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

set_port_default(8042);
set_threshold_defaults(150, 300);

env_creds(["HADOOP_YARN_NODE_MANAGER", "HADOOP"], "Yarn Node Manager");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/node/info";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my $nodeHealthy        = get_field("nodeInfo.nodeHealthy");
my $healthReport       = get_field("nodeInfo.healthReport");
my $lastNodeUpdateTime = get_field_float("nodeInfo.lastNodeUpdateTime");
my $node_version       = get_field("nodeInfo.nodeManagerVersion");

my $lag = sprintf("%d", time - $lastNodeUpdateTime/1000.0);

# For some reason the content of this is blank when API docs say it should be 'Healthy', but my nodes work so this isn't critical
$healthReport = "<blank>" unless $healthReport;

$msg = sprintf("node $host healthy = %s, healthReport = '%s', %d secs since last node report", ( $nodeHealthy ? "true" : "false"), $healthReport, $lag);
check_thresholds($lag);
$msg .= ", version $node_version" if $verbose;
$msg .= sprintf(" | 'last node update lag'=%ds%s", $lag, msg_perf_thresholds(1));

quit $status, $msg;
