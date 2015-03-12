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

$DESCRIPTION = "Nagios Plugin to check a Spark cluster for dead workers via the Spark Master HTTP interface

Tested on Apache Spark 0.8.1 and 0.9.1 standalone and 0.9.0 on Cloudera CDH 5.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use LWP::UserAgent;

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8080);
# port 8080 is usually taken, CDH sets it to 18080
#set_port_default(18080);

set_threshold_defaults(0, 0);

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
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "$host:$port";

my $html = curl $url, "Spark Master";

$html =~ /Spark Master at spark:\/\//i or quit "UNKNOWN", "returned html implies this is not the Spark Master, did you connect to the wrong service/host/port? Apache Spark defaults to port 8080 but in Cloudera CDH it defaults to port 18080. Also try incrementing the port number as Spark will bind to a port number 1 higher if the initial port is already occupied by another process";

$html =~ /Workers:.*?(\d+)/i or quit "UNKNOWN", "failed to determine spark cluster workers. $nagios_plugins_support_msg";
my $total_workers = $1;
my $alive_workers = 0;
my $dead_workers  = 0;
foreach(split("\n", $html)){
    if(/DEAD/i){
        $dead_workers++;
    } elsif(/ALIVE/i){
        $alive_workers++
    }
}
$msg .= "$dead_workers dead workers";
check_thresholds($dead_workers);
$msg .= ", $alive_workers alive workers | dead_workers=$dead_workers";
msg_perf_thresholds();
$msg .= " alive_workers=$alive_workers";
if( ( $alive_workers + $dead_workers ) != $total_workers ){
    quit "UNKNOWN", "ERROR alive ($alive_workers) + dead workers ($dead_workers) != total workers ($total_workers)!!! $nagios_plugins_support_msg"
}

quit $status, $msg;
