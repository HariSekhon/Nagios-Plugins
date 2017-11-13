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

$DESCRIPTION = "Nagios Plugin to check Hadoop HDFS replication via NameNode JMX API

Raises Critical on any missing or corrupt blocks, with configurable thresholds for under-replicated blocks. Also reports excess blocks and blocks pending replication

See also check_hadoop_dfs.pl and check_hadoop_namenode.pl for earlier implementations of replication checking using dfsadmin and the old NameNode JSP respectively

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

$VERSION = "0.2";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(0, 99999);
set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=FSNamesystem";

my $content = curl $url, "NameNode";

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by NameNode at '$url'";
};
#vlog3(Dumper($json));

my @beans = get_field_array("beans");

my $found_mbean = 0;

foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=FSNamesystem";
    $found_mbean = 1;
    my $pending_repl = get_field2_int($_, "PendingReplicationBlocks");
    my $pending_del  = get_field2_int($_, "PendingDeletionBlocks");
    my $under_repl   = get_field2_int($_, "UnderReplicatedBlocks");
    my $sched_repl   = get_field2_int($_, "ScheduledReplicationBlocks");
    my $corrupt      = get_field2_int($_, "CorruptBlocks");
    my $excess       = get_field2_int($_, "ExcessBlocks");
    my $missing      = get_field2_int($_, "MissingBlocks");
    my $post_misrepl = get_field2_int($_, "PostponedMisreplicatedBlocks");

    $msg  = sprintf("hdfs blocks missing: %d, corrupt: %d, under-replicated: %d", $missing, $corrupt, $under_repl);
    critical if $missing;
    critical if $corrupt;
    check_thresholds($under_repl);
    $msg .= sprintf(", excess: %d, replication pending: %d, scheduled: %d, deletion pending: %d, postponed misreplicated: %d | 'hdfs blocks missing'=%d 'hdfs blocks corrupt='%d 'hdfs blocks under-replicated'=%d", $excess, $pending_repl, $sched_repl, $pending_del, $post_misrepl, $missing, $corrupt, $under_repl);
    msg_perf_thresholds();
    $msg .= sprintf(" 'hdfs excess blocks'=%d 'hdfs blocks pending replication'=%d 'hdfs blocks scheduled for replication'=%d 'hdfs blocks pending deletion'=%d 'hdfs blocks postponed misreplicated'=%d", $excess, $pending_repl, $sched_repl, $pending_del, $post_misrepl, $missing, $corrupt, $under_repl);
    last;
}
quit "UNKNOWN", "failed to find FSNamesystem mbean" unless $found_mbean;

quit $status, $msg;
