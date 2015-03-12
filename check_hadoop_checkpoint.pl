#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#  Date: 2013-07-29 19:07:40 +0100 (Mon, 29 Jul 2013)
#
#  Idea dates back a few years earlier at least circa 2010-2012 that I used to run
#  but was never release grade and another implementation I initially started in 2013
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop HDFS last checkpoint lag via NameNode JMX

Tests time since last HDFS checkpoint against warning/critical thresholds in seconds

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

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
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(50070);
set_threshold_defaults(3700, 7200);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");
%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx";

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
my $last_checkpoint;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=FSNamesystem";
    $found_mbean = 1;
    $last_checkpoint = get_field2($_, "LastCheckpointTime");
    last;
}
quit "UNKNOWN", "failed to find namenode's FSNamesystem mbean" unless $found_mbean;

my $lag = time - floor($last_checkpoint/1000);
if($lag < 0){
    unknown;
    $msg .= "HDFS last checkpoint is in the future!! Check NTP between hosts. ";
}
$msg .= "HDFS last checkpoint $lag secs ago";
check_thresholds($lag);
$msg .= " | 'lag since last checkpoint'=${lag}s";
msg_perf_thresholds();

quit $status, $msg;
