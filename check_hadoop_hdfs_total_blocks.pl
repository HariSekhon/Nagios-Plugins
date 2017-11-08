#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-08-24 12:20:34 +0100 (Fri, 24 Aug 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# forked from check_hadoop_namenode.pl

$DESCRIPTION = "Nagios Plugin to check the number of total blocks via NameNode JSP

Works against either the Active or Standby NameNode in an HA configuration

Useful in track as it relates to Namenode JVM tuning which depends on metadata, primarily number of blocks.

DEPRECATED - does not work on Hadoop 2.7 as JSP was removed and replaced with AJAX calls

See check_hadoop_hdfs_total_blocks.py for a replacement that works with Hadoop 2.5 - 2.7 using the JMX API

See also check_hadoop_namenode_heap.pl for heap size checks

Tested on Hortonworks HDP 2.2 (Hadoop 2.6.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6";

$VERSION = "0.9.4";

use strict;
use warnings;
use LWP::Simple '$ua';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $namenode_urn = "dfshealth.jsp";

set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

%options = (
    %hostoptions,
    %thresholdoptions,
);


get_options();

$host = validate_host($host, "NameNode");
$port = validate_port($port, "NameNode");

my $url;

validate_thresholds(1, 1, {
                        "simple"   => "upper",
                        "integer"  => 1,
                        "positive" => 1,
                        });

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$url   = "http://$host:$port/$namenode_urn";
my $url_name = "namenode $host";

my $content;
$content = curl $url, "$url_name DFS overview";

my $total_blocks;
if($content =~ /(\d+)\s+blocks/){
    $total_blocks = $1;
} else {
    quit "UNKNOWN", "failed to find total block count";
}

$status = "OK";
$msg = "HDFS cluster has $total_blocks total blocks";
check_thresholds($total_blocks);
$msg .= " | total_hdfs_blocks=$total_blocks";
msg_perf_thresholds();

quit $status, $msg;
