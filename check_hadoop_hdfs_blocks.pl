#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-08-24 12:20:34 +0100 (Fri, 24 Aug 2012)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# forked from check_hadoop_namenode.pl

$DESCRIPTION = "Nagios Plugin to check the number of total blocks on the HDFS NameNode (works against either the Active or Standby NameNode in an HA configuration) via the Namenode JSP pages in order to detect when you need to tune JVM heap size up.

See also check_hadoop_namenode.pl for heap size and block checks

Tested on Hortonworks 2.2 (Apache 2.6.0)";

$VERSION = "0.9.3";

use strict;
use warnings;
use LWP::Simple '$ua';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $namenode_urn             = "dfshealth.jsp";

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
