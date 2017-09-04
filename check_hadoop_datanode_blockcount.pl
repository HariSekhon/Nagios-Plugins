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

Tested on CDH 4.x and Apache Hadoop 2.5.2, 2.6.4, 2.7.2";

$VERSION = "0.4";

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
$msg = "no scan errors since restort on datanode $host";

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $blockScannerReportAll = curl "http://$host:$port/blockScannerReport", "datanode $host";
my @blockScannerReport = split /\n/, $blockScannerReportAll; 

if($blockScannerReportAll =~ /block scanner .*not running/i){
            quit "UNKNOWN", "Periodic block scanner is not running. Please check the datanode log if this is unexpected. Perhaps you have dfs.block.scanner.volume.bytes.per.second = 0 in your hdfs-site.xml?";
	}



my $block_errors = 0;
foreach my $blockScannerReport (@blockScannerReport) {
	if($blockScannerReport =~ /Block scan errors since restart\s+:\s+(\d+)/){
	    $block_errors += $1;
	} 
}

if ($block_errors>0) {

	$status = "WARN";
	$msg = "$block_errors scan errors since restart on datanode $host";

}


quit $status, $msg;
