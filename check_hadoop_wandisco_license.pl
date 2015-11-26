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

$DESCRIPTION = "Nagios Plugin to check the WANdisco Non-Stop Hadoop License via NameNode JMX

Checks thresholds against the number of days left on the license

Written and tested on Hortonworks HDP 2.1 and WANdisco Non-Stop Hadoop 1.9.8";

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
use POSIX qw/floor strftime/;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(50070);

set_threshold_defaults(31, 15);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $eval_ok;

%options = (
    %hostoptions,
    "eval-ok"   =>  [ \$eval_ok,    "Returns OK if license type is evaluation (defaults to raising warning)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/eval-ok/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(1, 1, { "simple" => "lower", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=NamenodeLicenseMetrics";

$json = curl_json $url, "NameNode";

# Test sample
#$json = decode_json('{
#  "beans" : [ {
#    "name" : "Hadoop:service=NameNode,name=NamenodeLicenseMetrics",
#    "modelerType" : "NamenodeLicenseMetrics",
#    "tag.Context" : "nsnn",
#    "tag.ProductType" : "WAN",
#    "tag.LicenseType" : "EVALUATION",
#    "tag.AllowedIps" : "[]",
#    "tag.Hostname" : "cdh1",
#    "End" : 1419984000000,
#    "Start" : 1389465436000,
#    "AllowedDatanodes" : 35,
#    "RemainingDatanodes" : 29,
#    "RemainingTime" : 25177829095,
#    "AllowedNameNodes" : 6
#  } ]
#}');

my @beans = get_field_array("beans");

my $found_mbean = 0;
my $AllowedDatanodes;
my $AllowedNameNodes;
my $End;
my $LicenseType;
my $RemainingDatanodes;
my $RemainingTime;
my $Start;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=NamenodeLicenseMetrics";
    $found_mbean = 1;
    $AllowedDatanodes   = get_field2($_, "AllowedDatanodes");
    $AllowedNameNodes   = get_field2($_, "AllowedNameNodes");
    $End                = get_field2($_, "End");
    $LicenseType        = get_field2($_, 'tag\.LicenseType');
    $RemainingDatanodes = get_field2($_, "RemainingDatanodes");
    $RemainingTime      = get_field2($_, "RemainingTime");
    $Start              = get_field2($_, "Start");
    last;
}
unless($found_mbean){
    quit "UNKNOWN", "failed to find NamenodeLicenseMetrics mbean. Perhaps this isn't running the WANdisco Non-Stop Hadoop product? Alternatively $nagios_plugins_support_msg_api" unless $found_mbean;
}

if($LicenseType eq "EVALUATION" and not $eval_ok){
    warning;
} else {
    $LicenseType = lc $LicenseType;
}

# These are all in millisecs
$Start         /= 1000;
$End           /= 1000;
$RemainingTime /= 1000;

my $remaining_days = floor($RemainingTime / 86400);

$msg = sprintf("WANdisco Non-Stop Hadoop '%s' license ", $LicenseType);
if($remaining_days < 0){
    $msg .= sprintf("EXPIRED %d days ago", $remaining_days);
} else {
    $msg .= sprintf("%d days remaining", $remaining_days);
}
check_thresholds($remaining_days);
$msg .= sprintf(", start '%s', end '%s', allowed namenodes = %d, allowed datanodes = %d, remaining datanodes = %d | 'license days left'=%d%s 'allowed namenodes'=%d 'allowed datanodes'=%d 'remaining datanodes'=%d", strftime("%F %T", localtime($Start)), strftime("%F %T", localtime($End)), $AllowedNameNodes, $AllowedDatanodes, $RemainingDatanodes, $remaining_days, msg_perf_thresholds(1, 1), $AllowedNameNodes, $AllowedDatanodes, $RemainingDatanodes);

quit $status, $msg;
