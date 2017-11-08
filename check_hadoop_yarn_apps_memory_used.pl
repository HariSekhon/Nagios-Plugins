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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn app memory via Resource Manager JMX API

Optional thresholds on % used memory to aid in capacity planning

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.4";

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

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0, "min" => 0, "max" => 100 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:*";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
#vlog3(Dumper($json));

my @beans = get_field_array("beans");

my $found_mbean = 0;

foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=ResourceManager,name=QueueMetrics,q0=root";
    $found_mbean++;
    my $available_mb   = get_field2_float($_, "AvailableMB");
    my $allocated_mb   = get_field2_float($_, "AllocatedMB");
    my $total_mb       = $available_mb + $allocated_mb;
    my $pc_used        = sprintf("%.1f", $allocated_mb / $total_mb * 100);
    $msg .= "$pc_used% yarn app memory used";
    check_thresholds($pc_used);
    if($verbose){
        $msg .= " [${allocated_mb}MB/${total_mb}MB]";
    } else {
        $msg .= " [" . ( $allocated_mb ? human_units($allocated_mb*1024*1024) : 0 ) . "/" . human_units($total_mb*1024*1024) . "]";
    }
    $msg .= " | ";
    $msg .= "'% Yarn App Memory Used'=${pc_used}%";
    msg_perf_thresholds();
    $msg .= "0;100; 'Allocated Yarn App Memory'=${allocated_mb}MB;;;0;${total_mb}MB";
    last;
}

quit "UNKNOWN", "failed to find mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
