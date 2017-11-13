#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-29 01:01:21 +0000 (Tue, 29 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of blocks on a Hadoop HDFS Datanode via it's blockScannerReport

Specify --port 1022 for Kerberized clusters

Tested on CDH 4.x and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

my $default_port = 50075;
$port = $default_port;

# This is based on experience, real clusters seem to run in to problems after 300,000 blocks per DN. Cloudera Manager also alerts around this point
my $default_warning  = 300000;
my $default_critical = 500000;

$warning  = $default_warning;
$critical = $default_critical;

env_creds(["HADOOP_DATANODE", "HADOOP"], "Hadoop Datanode");

%options = (
    %hostoptions,
    %thresholdoptions,
);

@usage_order = qw/host port warning critical/;
get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $blockScannerReport = curl "http://$host:$port/blockScannerReport", "datanode $host";

my $block_count;
if($blockScannerReport =~ /Total Blocks\s+:\s+(\d+)/){
    $block_count = $1;
#} elsif($blockScannerReport =~ /Periodic block scanner is not running\. Please check the datanode log if this is unexpected/){
} elsif($blockScannerReport =~ /block scanner .*not running/i){
    quit "UNKNOWN", "Periodic block scanner is not running. Please check the datanode log if this is unexpected. Perhaps you have dfs.block.scanner.volume.bytes.per.second = 0 in your hdfs-site.xml?";
} else {
    quit "CRITICAL", "failed to find total block count from blockScannerReport. If this is Hadoop 2.7+ this information does not appear in the block scanner report any more, please use another method. If this is definitely Hadoop <= 2.6 then $nagios_plugins_support_msg";
}

$msg = "$block_count blocks on datanode $host";

check_thresholds($block_count);

$msg .= " | block_count=$block_count";
msg_perf_thresholds();

quit $status, $msg;
