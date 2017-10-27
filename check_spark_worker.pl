#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-23 20:58:14 +0000 (Mon, 23 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Spark Worker via HTTP interface

Thresholds are optional to check the memory used % of the worker

Originally written for Apache Spark 0.8.1 / 0.9.0 standalone (also tested on 0.9.0 on Cloudera CDH 5.0), updated for 1.x.

Tested on Apache Spark standalone 1.3.1, 1.4.1, 1.5.1, 1.6.2";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8081);
# CDH sets it to 18081
#set_port_default(18081);

env_creds(["SPARK_WORKER", "SPARK"], "Spark Worker");

%options = (
    %hostoptions,
    %thresholdoptions,
);
$options{"P|port=s"}[1] =~ s/\)$/ for Apache, use 18081 for Cloudera CDH managed Spark - or the next port up if that port was already taken when Spark started)/;

@usage_order = qw/host port warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "$host:$port";

my $html = curl $url, "Spark Worker";

$html =~ /Spark Worker at /i or quit "UNKNOWN", "returned html implies this port is not a Spark Worker, did you connect to the wrong service/host/port? Apache Spark defaults to port 8081 but in Cloudera CDH it defaults to port 18081. Also try incrementing the port number as Spark will bind to a port number 1 higher if the initial port is already occupied by another process";

$html =~ /Cores:.*?(\d+)\s+.*(\d+)\s+Used/is or quit "UNKNOWN", "failed to determine spark worker cores. $nagios_plugins_support_msg";
my $cores             = $1;
my $cores_used        = $2;

$html =~ /Memory:.*?(\d+(?:\.\d+)?)\s*(\w+)\s+.*?(\d+(?:\.\d+)?)\s*(\w+)\s+Used/is or quit "UNKNOWN", "failed to determine spark worker memory. $nagios_plugins_support_msg";
my $memory            = $1;
my $memory_units      = $2;
my $memory_used       = $3;
my $memory_used_units = $4;

my $memory_bytes      = expand_units($memory, $memory_units);
my $memory_used_bytes = expand_units($memory_used, $memory_used_units);

my $memory_pc;
if($memory_used_bytes == 0 or $memory_bytes == 0){
    $memory_pc = 0;
} else {
    $memory_pc = sprintf("%.2f", $memory_used_bytes / $memory_bytes * 100);
}

$msg .= "worker memory used: $memory_pc%";
check_thresholds($memory_pc);
$msg .= " $memory_used$memory_used_units/$memory$memory_units, cores used: $cores_used/$cores | 'worker memory used %'=$memory_pc%";
msg_perf_thresholds();
$msg .= " 'worker memory total'=" . expand_units($memory, $memory_units) . "b 'worker memory used'=" . expand_units($memory_used, $memory_used_units) . "b";
$msg .= " cores=$cores 'cores used'=$cores_used";

quit $status, $msg;
