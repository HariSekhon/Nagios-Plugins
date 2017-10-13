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

$DESCRIPTION = "Nagios Plugin to check Spark cluster memory used % via the Spark Master HTTP interface

Originally written for Apache Spark 0.8.1 / 0.9.1 standalone (also tested on 0.9.0 on Cloudera CDH 5.0), updated for 1.x.

Tested on Apache Spark standalone 1.3.1, 1.4.1, 1.5.1, 1.6.2";

$VERSION = "0.3.0";

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

set_port_default(8080);
# port 8080 is usually taken, CDH sets it to 18080
#set_port_default(18080);

env_creds(["SPARK_MASTER", "SPARK"], "Spark Master");

%options = (
    %hostoptions,
    %thresholdoptions,
);
$options{"P|port=s"}[1] =~ s/\)$/ for Apache, use 18080 for Cloudera CDH managed Spark - or the next port up if that port was already taken when Spark started)/;

@usage_order = qw/host port warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "$host:$port";

my $html = curl $url, "Spark Master";

$html =~ /Spark Master at spark:\/\//i or quit "UNKNOWN", "returned html implies this is not the Spark Master, did you connect to the wrong service/host/port? Apache Spark defaults to port 8080 but in Cloudera CDH it defaults to port 18080. Also try incrementing the port number as Spark will bind to a port number 1 higher if the initial port is already occupied by another process";

$html =~ /Memory.*?(\d+(?:\.\d+)?)\s*(\w+)\s+Total.*?(\d+(?:\.\d+)?)\s*(\w+)\s+Used/ism or quit "UNKNOWN", "failed to determine spark cluster memory. $nagios_plugins_support_msg";
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

$msg .= "cluster memory used: $memory_pc%";
check_thresholds($memory_pc);
$msg .= " $memory_used$memory_used_units/$memory$memory_units | 'cluster memory used %'=$memory_pc%";
msg_perf_thresholds();
$msg .= " 'cluster memory total'=" . expand_units($memory, $memory_units) . "b 'cluster memory used'=" . expand_units($memory_used, $memory_used_units) . "b";

quit $status, $msg;
