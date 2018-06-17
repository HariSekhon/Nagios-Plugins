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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn Node Managers via Resource Manager JMX API

Thresholds apply to the total of lost + unhealthy Node Managers

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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
set_threshold_defaults(0, 0);

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Hadoop Resource Manager");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(1, 1, { "positive" => 1, "simple" => "upper", "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=ResourceManager,name=ClusterMetrics";

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

foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=ResourceManager,name=ClusterMetrics";
    $found_mbean = 1;
    my $active_NMs    = get_field2_int($_, "NumActiveNMs");
    my $decomm_NMs    = get_field2_int($_, "NumDecommissionedNMs");
    my $lost_NMs      = get_field2_int($_, "NumLostNMs");
    my $unhealthy_NMs = get_field2_int($_, "NumUnhealthyNMs");
    my $rebooted_NMs  = get_field2_int($_, "NumUnhealthyNMs");
    $msg = "node managers: $active_NMs active, $lost_NMs lost / $unhealthy_NMs unhealthy";
    check_thresholds($lost_NMs + $unhealthy_NMs);
    $msg .= ", $decomm_NMs decommissioned, $rebooted_NMs rebooted";
    $msg .= sprintf(" | 'active node managers'=%d 'lost node managers'=%d", $active_NMs, $lost_NMs);
    msg_perf_thresholds();
    $msg .= sprintf(" 'unhealthy node managers'=%d", $unhealthy_NMs);
    msg_perf_thresholds();
    $msg .= sprintf(" 'decommissioned node managers'=%d 'rebooted node managers'=%d", $decomm_NMs, $rebooted_NMs);
    last;
}
quit "UNKNOWN", "failed to find cluster metrics mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
