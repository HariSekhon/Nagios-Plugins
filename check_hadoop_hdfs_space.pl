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

$DESCRIPTION = "Nagios Plugin to check Hadoop HDFS Space % used via NameNode JMX

See also check_hadoop_hdfs_space.py for a Python version or check_hadoop_dfs.pl for an older implementation that parses dfsadmin output.

For CDH 6.x / Hadoop 3.x onwards you will need to use --port 9870

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 3.0";

$VERSION = "0.4.0";

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
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

# Hadoop 3.x / CDH 6.x+ - not enabling by default to maintain backwards compatibility with existing deployments
#set_port_default(9870);
set_port_default(50070);
set_threshold_defaults(80, 90);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");
%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1, "min" => 0, "max" => 100});

vlog2;
set_timeout();

$status = "OK";

my $mbean = "Hadoop:service=NameNode,name=FSNamesystemState";

my $url = "http://$host:$port/jmx?qry=$mbean";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by NameNode at '$url'";
};
vlog3(Dumper($json));

my @beans = get_field_array("beans");

my $found_mbean = 0;
my $pc_used;
my $files;
my $blocks;
my $used;
my $total;
foreach(@beans){
    next unless get_field2($_, "name") eq $mbean;
    $found_mbean = 1;
    $files   = get_field2_int($_, "FilesTotal");
    $blocks  = get_field2_int($_, "BlocksTotal");
    $used    = get_field2_int($_, "CapacityUsed");
    $total   = get_field2_int($_, "CapacityTotal");
    $pc_used = $used / $total * 100;
    last;
}
quit "UNKNOWN", "failed to find namenode NameNodeInfo mbean" unless $found_mbean;

$msg .= sprintf("%.1f%% HDFS used", $pc_used);
check_thresholds($pc_used);
$msg .= sprintf(" (%s/%s), in %d files spread across %s blocks", human_units($used), human_units($total), $files, $blocks);
$msg .= sprintf(" | 'HDFS %% space used'=%f%%", $pc_used);
msg_perf_thresholds();
$msg .= sprintf(" 'HDFS space used'=%db 'HDFS file count'=%d 'HDFS block count'=%d", $used, $files, $blocks);

quit $status, $msg;
