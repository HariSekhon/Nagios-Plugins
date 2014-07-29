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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn available memory for Yarn Apps via Resource Manager jmx

Optional thresholds on available memory in MB to aid in capacity planning

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

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

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "lower", "positive" => 1, "integer" => 0 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx";

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
    next unless get_field2($_, "name") eq "Hadoop:service=ResourceManager,name=QueueMetrics,q0=root";
    $found_mbean++;
    my $available_mb   = get_field2_float($_, "AvailableMB");
    $msg .= human_units($available_mb*1024*1024) . " available memory for Yarn apps";
    $msg .= " [${available_mb}MB]" if $verbose;
    check_thresholds($available_mb);
    $msg .= " | ";
    $msg .= "'Available Memory for Yarn apps'=${available_mb}MB";
    msg_perf_thresholds();
    last;
}

quit "UNKNOWN", "failed to find mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
