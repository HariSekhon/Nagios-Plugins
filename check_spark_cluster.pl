#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-23 20:58:14 +0000 (Mon, 23 Dec 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Spark cluster via the Spark Master HTTP interface

Optional thresholds can be applied to the number of Spark Workers

Tested on Apache Spark 0.8.1 and 0.9.1 standalone and 0.9.0 on Cloudera CDH 5.0";

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
validate_thresholds(undef, undef, { "simple" => "lower", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "$host:$port";

my $html = curl $url, "Spark Master";

$html =~ /Spark Master at spark:\/\//i or quit "UNKNOWN", "returned html implies this is not the Spark Master, did you connect to the wrong service/host/port? Apache Spark defaults to port 8080 but in Cloudera CDH it defaults to port 18080. Also try incrementing the port number as Spark will bind to a port number 1 higher if the initial port is already occupied by another process";

#$html =~ /Workers:.*?(\d+)/i or quit "UNKNOWN", "failed to determine spark cluster workers. $nagios_plugins_support_msg";
#my $workers           = $1;
my $workers = 0;
foreach(split("\n", $html)){
    /ALIVE/ && $workers++;
}
$html =~ /Cores:.*?(\d+)\s+Total.*(\d+)\s+Used/is or quit "UNKNOWN", "failed to determine spark cluster cores. $nagios_plugins_support_msg";
my $cores             = $1;
my $cores_used        = $2;
$html =~ /Memory:.*?(\d+(?:\.\d+)?)\s*(\w+)\s+Total.*?(\d+(?:\.\d+)?)\s*(\w+)\s+Used/is or quit "UNKNOWN", "failed to determine spark cluster memory. $nagios_plugins_support_msg";
my $memory            = $1;
my $memory_units      = $2;
my $memory_used       = $3;
my $memory_used_units = $4;
$html =~ /Applications:.*?(\d+).*?Running.*?(\d+).*?Completed/is or quit "UNKNOWN", "failed to determine spark applications. $nagios_plugins_support_msg";
my $apps_running      = $1;
my $apps_completed    = $2;

$msg .= "spark cluster workers: $workers";
check_thresholds($workers);
$msg .= ", cores used: $cores_used/$cores, memory used: $memory_used$memory_used_units/$memory$memory_units, applications running: $apps_running completed: $apps_completed | workers=$workers";
msg_perf_thresholds();
$msg .= " cores=$cores cores_used=$cores_used memory=" . expand_units($memory, $memory_units) . "b memory_used=" . expand_units($memory_used, $memory_used_units) . "b applications_running=$apps_running applications_completed=$apps_completed";

quit $status, $msg;
