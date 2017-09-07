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

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385) and Apache Hadoop 2.5.2, 2.6.4, 2.7.2";

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
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

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

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo";

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
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=NameNodeInfo";
    $found_mbean = 1;
    $pc_used = get_field2($_, "PercentUsed");
    if($pc_used =~ /^\d\.\d+e-\d+$/){
        $pc_used = 0;
    }
    if(! isFloat($pc_used)){
        quit "UNKNOWN", "PercentUsed is not a float! $nagios_plugins_support_msg";
    }
    $files   = get_field2_int($_, "TotalFiles");
    $blocks  = get_field2_int($_, "TotalBlocks");
    $used    = get_field2_int($_, "Used");
    $total   = get_field2_int($_, "Total");
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
