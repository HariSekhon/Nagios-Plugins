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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn Resource Manager Heap/Non-Heap Used % via jmx

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

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Hadoop Resource Manager");

my $non_heap      = 0;

%options = (
    %hostoptions,
    "non-heap"     => [ \$non_heap,  "Check Non-Heap memory used % against thresholds (default w=80%/c=90%)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/non-heap/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1 });

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

my $non = "";
my $Non = "";
if($non_heap){
    $non  = "non-";
    $Non  = "Non";
}
foreach(@beans){
    next unless get_field2($_, "name") eq "java.lang:type=Memory";
    $found_mbean = 1;
    my $max     = get_field2_int($_, "${Non}HeapMemoryUsage.max");
    my $used    = get_field2_int($_, "${Non}HeapMemoryUsage.used");
    my $used_pc = sprintf("%.2f", $used / $max * 100);
    
    $msg = sprintf("%s%% ${non}heap used (%s/%s)", $used_pc, human_units($used), human_units($max));
    check_thresholds($used_pc);
    $msg .= sprintf(" | '${non}heap used %%'=%s%%", $used_pc);
    msg_perf_thresholds();
    $msg .= sprintf(" '${non}heap used'=%sb '${non}heap max'=%sb '${non}heap committed'=%sb", $used, $max, get_field2_int($_, "${Non}HeapMemoryUsage.committed"));
    last;
}
quit "UNKNOWN", "failed to find memory mbean. $nagios_plugins_support_msg_api" unless $found_mbean;

quit $status, $msg;
