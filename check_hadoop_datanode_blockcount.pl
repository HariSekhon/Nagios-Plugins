#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-29 01:01:21 +0000 (Tue, 29 Oct 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the number of blocks on a Hadoop HDFS Datanode via it's blockScannerReport";

$VERSION = "0.3";

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

# This is based on experience, real clusters seem to run in to problems after 300,000 blocks per DN. Cloudera Manager also alerts around thsi point
my $default_warning  = 300000;
my $default_critical = 500000;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    "H|host=s"         => [ \$host,         "DataNode host to connect to" ],
    "P|port=s"         => [ \$port,         "DataNode HTTP port (default: $default_port)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive, default: $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive, default: $default_critical)" ],
);

@usage_order = qw/host port warning critical/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
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
} else {
    quit "CRITICAL", "failed to find total block count from blockScannerReport, $nagios_plugins_support_msg";
}

$msg = "$block_count blocks on datanode $host";

check_thresholds($block_count);

$msg .= " | block_count=$block_count";
msg_perf_thresholds();

quit $status, $msg;
