#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-29 01:01:21 +0000 (Tue, 29 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the number of blocks on a Hadoop HDFS Datanode via it's blockScannerReport";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple qw/get $ua/;

my $default_port = 50075;
$port = $default_port;

%options = (
    "H|host=s"         => [ \$host,         "DataNode host to connect to" ],
    "P|port=s"         => [ \$port,         "DataNode HTTP port (default: $default_port)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $blockScannerReport = curl "http://$host:$port/blockScannerReport";

my $block_count;
if($blockScannerReport =~ /Total Blocks\s+:\s+(\d+)/){
    $block_count = $1;
} else {
    quit "CRITICAL", "failed to find total block count from blockScannerReport, $nagios_plugins_support_msg";
}

$msg = "$block_count blocks on datanode $host";

check_thresholds($block_count);

$msg .= " | block_count=$block_count";
msg_perf_thresholds();

quit $status, $msg;
