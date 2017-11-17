#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-03 09:46:19 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the contents of a znode in ZooKeeper.

Useful for a wide variety of checks against ZooKeeper based services such as HBase, SolrCloud, NameNode & JobTracker HA ZKFC

Checks:

1. root znode (\"/\") exists ( we are successfully connected to ZooKeeper(s), tries all given ZooKeepers in turn )
2. given znode exists (useful for checking ephemeral znodes eg. HBase Master is reporting alive by holding ephemeral node in ZooKeeper)
3. given znode's literal contents, substring match (eg. server we expect is the Master. optional)
4. given znode's contents against regex (eg. one of the servers we expect is the Master, flexible, anchoring etc. optional)
5. given znode is not blank/empty (unless -d \"\" is intentionally specified)
6. given znode is ephemeral (optional)
7. given znode has children / no children znodes (optional. Useful when the child znodes are dynamic but you just need to check for their existence)
8. given znode's age against --warning/--critical thresholds (optional)

Checks 3-5 and 8 are skipped when specifying --null znodes

Tested on Apache ZooKeeper 3.3.6, 3.4.5, 3.4.6, 3.4.8, 3.4.11 and on Cloudera, Hortonworks and MapR.

================================================================================
                            Some useful examples:
================================================================================

* Check we have an active HBase Root Master (this is an ephemeral node that will disappear if Master is down):

check_hbase_master_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hbase/master --ephemeral
________________________________________________________________________________

* Check we have an HBase Root RegionServer assigned:

check_hbase_root_regionserver_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hbase/root-region-server
________________________________________________________________________________

* Check there are no HBase unassigned regions (should be blank hence -d \"\"):

check_hbase_unassigned_regions_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hbase/unassigned -d \"\" --no-child-znodes
________________________________________________________________________________

* Check there are HBase Backup Masters:

check_hbase_backup_masters_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hbase/backup-masters
________________________________________________________________________________

* Check given SolrCloud server is alive and holding it's ephemeral znode:

check_solrcloud_server_znode.pl -H <zookeepers> -z /solr/live_nodes/<solrhost>:8983_solr
    or
check_zookeeper_znode.pl -H <zookeepers> -z /solr/live_nodes/<solrhost>:8983_solr --null --ephemeral
________________________________________________________________________________

* Check HDFS NameNode HA ZKFC is working

check_hadoop_namenode_ha_zkfc_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hadoop-ha/nameservice1/ActiveStandbyElectorLock --ephemeral

(ActiveBreadCrumb doesn't change to reflect real state without ZKFC when tested on CDH 4.3, so may as well test only the ZKFC elector lock which is released if the NameNode for that ZKFC is down anyway)
________________________________________________________________________________

* Check MapReduce v1 JobTracker HA ZKFC is working

check_hadoop_jobtracker_ha_zkfc_znode.pl -H <zookeepers>
    or
check_zookeeper_znode.pl -H <zookeepers> -z /hadoop-ha/logicaljt/ActiveStandbyElectorLock --ephemeral

(ActiveBreadCrumb doesn't change to reflect real state without ZKFC when tested on CDH 4.3, so may as well test only the ZKFC elector lock which is released if the JobTracker for that ZKFC is down anyway)
________________________________________________________________________________

* Check Kafka broker is alive, extract its hostname and verify:

check_zookeeper_znode.pl -H <zookeepers> -z /brokers/ids/0 --ephemeral --data server1.domain.com --json-field host -v
________________________________________________________________________________

* Check Kafka consumer is online:

check_zookeeper_znode.pl -z /consumers/<group>/ids/<id> --ephemeral
________________________________________________________________________________

* Check Kafka consumer group offset:

./check_zookeeper_znode.pl -z /consumers/<group>/offsets/<topic>/<partition> -v

================================================================================

Here is an excellent blog post by my fellow Clouderans on HBase znodes (apparently this will change in C5 though):

http://blog.cloudera.com/blog/2013/10/what-are-hbase-znodes/


API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happens sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr, must use --null to skip checks other than existence
";

$VERSION = "0.7.2";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::ZooKeeper;
use Net::ZooKeeper qw/:DEFAULT :errors :log_levels/;

my $znode;
my $null;
my $expected_data;
my $expected_regex;
my $json_field;
my $check_ephemeral       = 0;
my $check_child_znodes    = 0;
my $check_no_child_znodes = 0;

%options = (
    %zookeeper_options,
    "z|znode=s"         => [ \$znode,                 "Znode to check exists. Useful for a variety of checks of ZooKeeper based services like HBase, SolrCloud, NameNode & JobTracker HA ZKFC" ],
    "n|null"            => [ \$null,                  "Do not check znode contents, use on null znodes such as SolrCloud /solr/live_nodes/<hostname>:8983_solr as the API segfaults when trying to retrieve data for these null znodes" ],
    "d|data=s"          => [ \$expected_data,         "Check given znode contains specific data (optional). This is a partial substring match, for more control use --regex with anchors. Careful when specifying non-printing characters which may appear as ?, may need to use regex to work around them with \".+\" to match any character" ],
    "r|regex=s"         => [ \$expected_regex,        "Check given znode contains data matching this case insensitive regex (optional). Checked after --data" ],
    "j|json-field=s"    => [ \$json_field,            "Require json znode contents and extract specific json field to check against --data and/or --regex (use field1.subfield2 for embedded fields, dot can be escaped with backslash for fields containing a literal dot)" ],
    "e|ephemeral"       => [ \$check_ephemeral,       "Check given znode is ephemeral (optional)" ],
    "child-znodes"      => [ \$check_child_znodes,    "Check given znode has child znodes (optional)" ],
    "no-child-znodes"   => [ \$check_no_child_znodes, "Check given znode does not have child znodes (optional)" ],
    %thresholdoptions,
);
@usage_order = qw/host port znode data regex json-field null ephemeral child-znodes no-child-znodes user password warning critical random-conn-order session-timeout/;

if($progname eq "check_hbase_backup_masters_znode.pl"){
    $znode = "/hbase/backup-masters";
} elsif($progname eq "check_hbase_master_znode.pl"){
    $znode = "/hbase/master";
    $check_ephemeral = 1;
} elsif($progname eq "check_hbase_root_regionserver_znode.pl"){
    $znode = "/hbase/root-region-server";
} elsif($progname eq "check_hbase_unassigned_regions_znode.pl"){
    $znode = "/hbase/unassigned";
    $expected_data  = "";
    $check_no_child_znodes = 1;
} elsif($progname eq "check_solrcloud_server_znode.pl"){
    # can't auto determine znode since it's based on the server's hostname
    $null = 1;
    $check_ephemeral = 1;
} elsif($progname eq "check_hadoop_namenode_ha_zkfc_znode.pl"){
    $znode = "/hadoop-ha/nameservice1/ActiveStandbyElectorLock";
    $check_ephemeral = 1;
} elsif($progname eq "check_hadoop_jobtracker_ha_zkfc_znode.pl"){
    $znode = "/hadoop-ha/logicaljt/ActiveStandbyElectorLock";
    $check_ephemeral = 1;
}

get_options();

my @hosts = validate_hosts($host, $port);
$znode = validate_znode($znode);
if($check_child_znodes and $check_no_child_znodes){
    usage "cannot specify both --child-znodes and --no-child-znodes simultaneously they are mutually exclusive";
}
validate_thresholds();

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

$expected_regex = validate_regex($expected_regex) if defined($expected_regex);
if($json_field){
    $json_field =~ /^([\w\\.-]+)$/ or usage "invalid --json-field, must be alphanumeric, dots and backslash";
    $json_field = $1;
    vlog_option "json field", $json_field;
}

vlog2;
set_timeout();

$status = "UNKNOWN";

connect_zookeepers(@hosts);

check_znode_exists($znode);

# we don't get a session id until after a call to the server such as exists() above
#my $session_id = $zkh->{session_id} or quit "UNKNOWN", "failed to determine ZooKeeper session id, possibly not connected to ZooKeeper?";
#vlog2 sprintf("session id: %s", $session_id);

$status = "OK";
if($null){
    $msg = "znode '$znode' exists";
} else {
    my $data = get_znode_contents($znode);
    if($json_field){
        $data = isJson($data) or quit "CRITICAL", "znode '$znode' data is not json as expected, got '$data'";
        $data = get_field2($data, $json_field);
    }

    if(defined($expected_data)){
        unless(index($data, $expected_data) != -1){
            quit "CRITICAL", "znode '$znode' data mismatch, expected: '$expected_data', got: '$data'";
        }
    }
    if(defined($expected_regex)){
        unless($data =~ $expected_regex){
            quit "CRITICAL", "znode '$znode' data mismatch, expected regex: '$expected_regex', got: '$data'";
        }
    }
    if((!defined($expected_data))){
        vlog2 "no expected data defined, checking znode is not blank";
        if($data =~ /^\s*$/){
            quit "CRITICAL", "znode '$znode' is empty!" . ( $verbose ? " (if this is intentional supply -d \"\")" : "" );
        }
    }

    $msg = "retrieved znode '$znode' from zookeeper$plural '@hosts'";
    $msg .= sprintf(", value='%s'", $data) if $verbose;
}

if($check_ephemeral){
    if($zk_stat->{ephemeral_owner}){
        vlog2 "znode '$znode' is ephemeral";
    } else {
        quit "CRITICAL", "znode '$znode' is not ephemeral";
    }
}

if($check_child_znodes or $check_no_child_znodes){
    vlog2 "checking for child znodes";
    my @child_znodes = $zkh->get_children($znode);
    my $child_znode_num = scalar @child_znodes;
    vlog3 "$child_znode_num child znodes detected" . ( @child_znodes ? ":\n\n" . join("\n", @child_znodes) . "\n" : "" );
    if($check_child_znodes){
        if(not @child_znodes){
            quit "CRITICAL", "no znodes detected under $znode";
        } else {
            $msg .= ", $child_znode_num child znodes";
        }
    } elsif($check_no_child_znodes){
        if(@child_znodes){
            quit "CRITICAL", "$child_znode_num znodes detected under $znode";
        } else {
            $msg .= ", no child znodes";
        }
    }
}

get_znode_age($znode);
$msg .= sprintf(", last modified %s secs ago", sec2human($znode_age_secs));
check_thresholds($znode_age_secs);

if($null){
    $msg .= ( $verbose ? " (--null specified, remaining checks skipped)" : "");
}

vlog2;
quit $status, $msg;
