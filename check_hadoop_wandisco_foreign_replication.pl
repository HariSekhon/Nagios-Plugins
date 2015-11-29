#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://docs.wandisco.com/bigdata/nsnn/1.9h/api.html

$DESCRIPTION = "Nagios Plugin to check the WANdisco Non-Stop Hadoop blocks pending foreign (cross-DC) replication via NameNode JMX

Checks thresholds against the number of blocks pending foreign replication.

Written and tested on Hortonworks HDP 2.1 and WANdisco Non-Stop Hadoop 1.9.8";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON::XS;
use LWP::Simple '$ua';
use POSIX qw/floor strftime/;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(50070);

set_threshold_defaults(1000, 100000);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=FSNamesystem";

$json = curl_json $url, "NameNode";

# Test sample
#$json = decode_json('{
#  "beans" : [ {
#      "name" : "Hadoop:service=NameNode,name=GeoNamesystem",
#      "modelerType" : "GeoNamesystem",
#      "tag.Context" : "dfs",
#      "tag.HAState" : "active",
#      "tag.Hostname" : "hdp1",
#      "pendingForeignReplication" : 2,
#      "BlockIdRangeLow" : 0,
#      "BlockIdRangeHigh" : 1537228672809129300,
#      "LastWrittenTransactionId" : 703,
#      "MissingBlocks" : 0,
#      "ExpiredHeartbeats" : 0,
#      "TransactionsSinceLastCheckpoint" : 347,
#      "TransactionsSinceLastLogRoll" : 342,
#      "LastCheckpointTime" : 1394804991624,
#      "CapacityTotalGB" : 59.0,
#      "CapacityUsedGB" : 2.0,
#      "CapacityRemainingGB" : 49.0,
#      "TotalLoad" : 5,
#      "BlocksTotal" : 44,
#      "FilesTotal" : 88,
#      "PendingReplicationBlocks" : 0,
#      "UnderReplicatedBlocks" : 2,
#      "CorruptBlocks" : 0,
#      "ScheduledReplicationBlocks" : 0,
#      "PendingDeletionBlocks" : 0,
#      "ExcessBlocks" : 0,
#      "PostponedMisreplicatedBlocks" : 0,
#      "PendingDataNodeMessageCount" : 0,
#      "MillisSinceLastLoadedEdits" : 0,
#      "BlockCapacity" : 2097152,
#      "TotalFiles" : 88
#    } ]
#}');

my @beans = get_field_array("beans");

my $found_mbean = 0;
my $pendingForeignReplication;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=FSNamesystem";
    $found_mbean = 1;
    $pendingForeignReplication = get_field2($_, "pendingForeignReplication");
    last;
}
unless($found_mbean){
    quit "UNKNOWN", "failed to find GeoNamesystem mbean. Perhaps this isn't running the WANdisco Non-Stop Hadoop product? Alternatively $nagios_plugins_support_msg_api" unless $found_mbean;
}

$msg = sprintf("WANdisco Non-Stop Hadoop blocks pending foreign replication = %d", $pendingForeignReplication);
check_thresholds($pendingForeignReplication);
$msg .= sprintf(" | 'blocks pending foreign replication'=%d", $pendingForeignReplication);
msg_perf_thresholds();

quit $status, $msg;
