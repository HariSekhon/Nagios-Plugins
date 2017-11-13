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

$DESCRIPTION = "Nagios Plugin to check Hadoop Yarn metrics such as Apps/Containers/Nodes via the Resource Manager's REST API

Can specifiy one or more metrics to output using --metrics, otherwise all metrics are output by default. Graphing perfdata is output for each selected metric. Recommended to explicitly select metrics as PNP4Nagios RRD breaks when the number of perfdata changes if more metrics are added to Hadoop at a later time.

Optional thresholds can be specified for a metric if specifying only one metric.

Thresholds default to upper boundaries, but to make them lower boundaries use standard Nagios threshold syntax <lower>:<upper> eg 5: for a minimum of 5 (inclusive) with no upper boundary to apply to things like activeNodes or availableMB.

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

my $metriclist;

%options = (
    %hostoptions,
    "m|metrics=s"      =>  [ \$metriclist,  "List of metrics to output, comma separated (if not specified defaults to outputting all metrics)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/metrics/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my @metrics;
if(defined($metriclist)){
    @metrics = split(/\s*,\s*/, $metriclist);
    foreach my $metric (@metrics){
        $metric =~ /^([\w_-]+)$/;
        $metric = $1;
        vlog_option "metric", $metric;
    }
    @metrics or usage "no valid metrics specified";
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 0 });
if(@metrics){
    @metrics = uniq_array @metrics;
    if(@metrics != 1 and ($warning or $critical)){
        usage "cannot specify thresholds if specifying more than one metric";
    }
}

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster/metrics";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my $msg2;
my %metrics = get_field_hash("clusterMetrics");

foreach(@metrics){
    unless(defined($metrics{$_})){
        quit "UNKNOWN", "metric '$_' not found. Check you have specified a valid metric by omitting --metrics to show all metrics. If you're sure you specified a valid metrics then $nagios_plugins_support_msg_api";
    }
}
foreach(sort keys %metrics){
    vlog2 "$_ = $metrics{$_}";
}
vlog2;

sub msg_metric($){
    my $key = shift;
    $msg  .= "$key=$metrics{$key}";
    $msg2 .= "'$key'=$metrics{$key}";
    $msg2 .= "MB" if($key =~ /MB$/);
    if(scalar @metrics == 1){
        check_thresholds($metrics{$key});
        $msg2 .= msg_perf_thresholds(1);
    }
    $msg  .= ", ";
    $msg2 .= " ";
}

foreach my $key (sort keys %metrics){
    if(@metrics){
        if(grep { $key eq $_ } @metrics){
            msg_metric($key);
        }
    } else {
        msg_metric($key);
    }
}
$msg =~ s/, $//;
$msg .= " | $msg2";

quit $status, $msg;
