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

$DESCRIPTION = "Nagios Plugin to check Hadoop DataNodes via NameNode JMX API

Configurable warning/critical thresholds for number of dead datanodes and configurable warning threshold for stale datanodes

See also check_hadoop_dfs.pl for another implementation of datanode checks from a few years back that parses dfsadmin instead.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.3.0";

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

set_threshold_defaults(0, 1);
set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $stale_threshold = 0;

%options = (
    %hostoptions,
    %thresholdoptions,
    "stale-threshold=s" =>  [ $stale_threshold, "Stale datanodes warning threshold (inclusive, default 0)" ],
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1 });
validate_int($stale_threshold, "stale threshold", 0, 10000);

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=FSNamesystemState";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by NameNode at '$url'";
};
#vlog3(Dumper($json));

my @beans = get_field_array("beans");

my $found_mbean = 0;

foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=FSNamesystemState";
    $found_mbean = 1;
    my $live        = get_field2_int($_, "NumLiveDataNodes");
    my $dead        = get_field2_int($_, "NumDeadDataNodes");
    my $stale       = get_field2_int($_, "NumStaleDataNodes");
    my $decom;
    my $decom_live;
    my $decom_dead;
    # Hadoop 2.2 doesn't have these stats
    if(defined($$_{"NumDecommissioningDataNodes"})){
        $decom       = get_field2_int($_, "NumDecommissioningDataNodes");
        $decom_live  = get_field2_int($_, "NumDecomLiveDataNodes");
        $decom_dead  = get_field2_int($_, "NumDecomDeadDataNodes");
    }
    $msg =  "datanodes: $live live, $dead dead";
    check_thresholds($dead);
    $msg .= ", $stale stale";
    $msg .= " (w=$stale_threshold)" if $verbose;
    warning if($stale > $stale_threshold);
    if(defined($decom)){
        $msg .= ", $decom decommissioning, $decom_live live decommissioning, $decom_dead dead decommissioning";
    }
    $msg .= " | ";
    $msg .= sprintf("'live datanodes'=%d 'dead datanodes'=%d", $live, $dead);
    msg_perf_thresholds();
    if(defined($decom)){
        $msg .= sprintf(" 'stale datanodes'=%d;%d 'decommissioning datanodes'=%d 'decommissioning live datanodes'=%d 'decommissioning dead datanodes'=%d", $stale, $stale_threshold, $decom, $decom_live, $decom_dead);
    }
    last;
}
quit "UNKNOWN", "failed to find FSNamesystemState mbean" unless $found_mbean;

quit $status, $msg;
