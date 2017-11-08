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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn app stats via the Resource Manager's REST API

Optional thresholds are applied to the number of running apps on the cluster.

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0), HDP 2.6 (Hadoop 2.7.3) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster/appstatistics";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

$msg = "app stats: ";
my @stats = get_field_array("appStatInfo.statItem");

my %stats;
foreach (@stats){
    $stats{get_field2($_, "state")} = get_field2($_, "count");
}
foreach (sort keys %stats){
    vlog2 "$_ = $stats{$_}";
}
vlog2;

$msg = "yarn apps stats for cluster: ";
my $msg2;
my $state;
foreach(qw/RUNNING NEW NEW_SAVING SUBMITTED ACCEPTED FAILED KILLED FINISHED/){
    $state = lc($_);
    $msg  .= "$state = $stats{$_}";
    if($state eq "running"){
        check_thresholds($stats{$_});
    }
    $msg .= ", ";
    $msg2 .= sprintf("'%s'=%d%s", $state, $stats{$_},
        (grep({ $state eq $_ } qw/new new_saving running submitted/) ? "" : "c") );
    if($state eq "running"){
        $msg2 .= msg_perf_thresholds(1);
    }
    $msg2 .= " ";
}
$msg =~ s/, $//;
$msg .= " | $msg2";

vlog2
quit $status, $msg;
