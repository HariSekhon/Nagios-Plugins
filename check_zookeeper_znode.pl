#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-03 09:46:19 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the contents of a znode in ZooKeeper.

Useful for a wide variety of checks against ZooKeeper based services such as HBase, SolrCloud, NameNode & JobTracker HA ZKFC

Checks:

1. root znode (\"/\") exists ( we are successfully connected to ZooKeeper(s), retries all ZooKeepers )
2. given znode exists (useful for checking ephemeral znodes eg. HBase Master is reporting alive by holding ephemeral node in ZooKeeper)
3. given znode's literal contents, substring match (eg. server we expect is the Master. optional)
4. given znode's contents against regex (eg. one of the servers we expect is the Master, flexible, anchoring etc. optional)
5. given znode is not blank/empty (unless -d \"\" is intentionally specified)
6. given znode is ephemeral (optional)
7. given znode has children / no children znodes (optional. Useful when the child znodes are dynamic but you just need to check for their existence)
8. given znode's age against --warning/--critical thresholds (optional)

Checks 3-5 and 8 are skipped when specifying --null znodes

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

================================================================================

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr, must use --null to skip checks other than existence
";

$VERSION = "0.5";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    use lib "/usr/local/lib";
}
use HariSekhonUtils;
use HariSekhon::ZooKeeper;
use Net::ZooKeeper qw/:DEFAULT :errors :log_levels/;

my $default_zk_timeout = 2;
my $zk_timeout = $default_zk_timeout;

my $random_conn_order = 0;

my $znode;
my $null;
my $expected_data;
my $expected_regex;
my $check_ephemeral       = 0;
my $check_child_znodes    = 0;
my $check_no_child_znodes = 0;

$port = $ZK_DEFAULT_PORT;

%options = (
    "H|host=s"          => [ \$host,                  "ZooKeeper node(s) to connect to, should be a comma separated list of ZooKeepers the same as are configured on the ZooKeeper servers themselves (node1:$ZK_DEFAULT_PORT,node2:$ZK_DEFAULT_PORT,node3:$ZK_DEFAULT_PORT). It takes longer to connect to 3 ZooKeepers than just one of them (around 5 secs per ZooKeeper specified + (session-timeout x any offline ZooKeepers) so you will need to increase --timeout). Connection order is deterministic and will be tried in the order specified unless --random-conn-order" ],
    "P|port=s"          => [ \$port,                  "Port to connect to on ZooKeepers for any nodes not suffixed with :<port> (defaults to $ZK_DEFAULT_PORT)" ],
    "z|znode=s"         => [ \$znode,                 "Znode to check exists. Useful for a variety of checks of ZooKeeper based services like HBase, SolrCloud, NameNode & JobTracker HA ZKFC" ],
    "n|null"            => [ \$null,                  "Do not check znode contents, use on null znodes such as SolrCloud /solr/live_nodes/<hostname>:8983_solr as the API segfaults when trying to retrieve data for these null znodes" ],
    "d|data=s"          => [ \$expected_data,         "Check given znode contains specific data (optional). This is a partial substring match, for more control use --regex with anchors. Careful when specifying non-printing characters which may appear as ?, may need to use regex to work around them with \".+\" to match any character" ],
    "r|regex=s"         => [ \$expected_regex,        "Check given znode contains data matching this case insensitive regex (optional). Checked after --data" ],
    "e|ephemeral"       => [ \$check_ephemeral,       "Check given znode is ephemeral (optional)" ],
    "child-znodes"      => [ \$check_child_znodes,    "Check given znode to has child znodes (optional)" ],
    "no-child-znodes"   => [ \$check_no_child_znodes, "Check given znode to not have child znodes (optional)" ],
    "u|user=s"          => [ \$user,                  "User to connect with (Not tested. YMMV. optional)" ],
    "p|password=s"      => [ \$password,              "Password to connect with (Not tested. YMMV. optional)" ],
    "w|warning=s"       => [ \$warning,               "Warning  threshold or ran:ge (inclusive) for znode age (optional)" ],
    "c|critical=s"      => [ \$critical,              "Critical threshold or ran:ge (inclusive) for znode age (optional)" ],
    "random-conn-order" => [ \$random_conn_order,     "Randomize connection order" ],
    "session-timeout=s" => [ \$zk_timeout,            "ZooKeeper session timeout in secs (default: $default_zk_timeout). This determines how long to wait for connection to downed ZooKeepers and affects total execution time" ],
);

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

@usage_order = qw/host port znode data regex null ephemeral child-znodes no-child-znodes user password warning critical random-conn-order session-timeout/;
get_options();

$port = isPort($port) or usage "invalid ZooKeeper port given for all nodes";
defined($host) or usage "ZooKeepers not defined";
my @hosts = split(/\s*,\s*/, $host);
@hosts or usage "ZooKeepers not defined";
my $node_port;
foreach(my $i = 0; $i < scalar @hosts; $i++){
    undef $node_port;
    if($hosts[$i] =~ /:(\d+)$/){
        $node_port = isPort($1) or usage "invalid ZooKeeper port given for node " . $i+1;
        $hosts[$i] =~ s/:$node_port$//;
    }
    $hosts[$i]  = validate_host($hosts[$i]);
    validate_resolvable($hosts[$i]);
    $node_port  = $port unless defined($node_port);
    $hosts[$i] .= ":$node_port";
    vlog_options "port", $node_port;
}
$znode = validate_filename($znode, 0, "znode");
if($check_child_znodes and $check_no_child_znodes){
    usage "cannot specify both --child-znodes and --no-child-znodes simultaneously they are mutually exclusive";
}
validate_thresholds();

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

$expected_regex = validate_regex($expected_regex) if defined($expected_regex);

$zk_timeout = validate_float($zk_timeout, 0.001, 100, "zookeeper session timeout");

vlog2;
set_timeout();

$status = "UNKNOWN";
$msg    = "code error - msg not defined";

if($debug){
    Net::ZooKeeper::set_log_level(&ZOO_LOG_LEVEL_DEBUG);
} elsif($verbose > 3){
    Net::ZooKeeper::set_log_level(&ZOO_LOG_LEVEL_INFO);
} elsif($verbose > 1){
    Net::ZooKeeper::set_log_level(&ZOO_LOG_LEVEL_WARN);
}

# API may raise SIG PIPE on connection failure
local $SIG{'PIPE'} = sub { quit "UNKNOWN", "lost connection to ZooKeepers '" . join(",", @hosts) . "'"; };

$zk_timeout *= 1000;

if($random_conn_order){
    vlog2 "using random connection order";
    Net::ZooKeeper::set_deterministic_conn_order(0); # default
} else {
    vlog2 "setting deterministic connection order";
    Net::ZooKeeper::set_deterministic_conn_order(1);
}

my $zookeepers = join(",", @hosts);
vlog2 "connecting to ZooKeeper nodes: $zookeepers";
my $zkh = Net::ZooKeeper->new(  $zookeepers,
                                "session_timeout" => $zk_timeout
                             )
    || quit "CRITICAL", "failed to create connection object to ZooKeepers within $zk_timeout secs: $!";
vlog2 "ZooKeeper connection object created, won't be connected until we issue a call";

# Not tested auth yet
if(defined($user) and defined($password)){
    $zkh->add_auth('digest', "$user:$password");
}

my $session_timeout = ($zkh->{session_timeout} / 1000) or quit "UNKNOWN", "invalid session timeout determined from ZooKeeper handle, possibly not connected to ZooKeeper?";
vlog2 sprintf("session timeout is %.2f secs\n", $zk_timeout / 1000);

sub translate_zoo_error($){
    my $errno = shift;
    isInt($errno, 1) or code_error "non int passed to translate_zoo_error()";
    # this makes me want to cry, if anybody knows a better way of getting some sort of error translation out of this API please let me know!
    no strict 'refs';
    foreach(qw(
        ZOK
        ZSYSTEMERROR
        ZRUNTIMEINCONSISTENCY
        ZDATAINCONSISTENCY
        ZCONNECTIONLOSS
        ZMARSHALLINGERROR
        ZUNIMPLEMENTED
        ZOPERATIONTIMEOUT
        ZBADARGUMENTS
        ZINVALIDSTATE
        ZAPIERROR
        ZNONODE
        ZNOAUTH
        ZBADVERSION
        ZNOCHILDRENFOREPHEMERALS
        ZNODEEXISTS
        ZNOTEMPTY
        ZSESSIONEXPIRED
        ZINVALIDCALLBACK
        ZINVALIDACL
        ZAUTHFAILED
        ZCLOSING
        ZNOTHING
    )){
        if(&$_ == $errno){
            use strict 'refs';
            return "$errno $_";
        }
    }
    use strict 'refs';
    return "<failed to translate zookeeper error for error code: $errno>";
}

vlog2 "checking znode '/' exists to determine if we're properly connected to ZooKeeper";
my $connection_succeeded = 0;
# the last attempt will retry all zookeepers two more times if that zookeeper fails to connect
# to see this use -vv --session-timeout 0.001
for(my $i=0; $i < scalar @hosts; $i++){
    $zkh->exists("/") and $connection_succeeded = 1 and last;
}
$connection_succeeded or quit "CRITICAL", "connection error, failed to find znode '/': " . translate_zoo_error($zkh->get_error());
vlog2 "found znode '/', connection to zookeeper succeeded\n";

vlog3 "creating ZooKeeper stat object";
my $stat = $zkh->stat();
$stat or quit "UNKNOWN", "failed to create ZooKeeper stat object";
vlog3 "stat object created";

vlog2 "checking znode '$znode' exists";
$zkh->exists($znode, 'stat' => $stat) or quit "CRITICAL", "znode '$znode' does not exist! ZooKeeper returned: " . translate_zoo_error($zkh->get_error());
$stat or quit "UNKNOWN", "failed to get stats from znode $znode";
vlog2 "znode '$znode' exists";

# we don't get a session id until after a call to the server such as exists() above
#my $session_id = $zkh->{session_id} or quit "UNKNOWN", "failed to determine ZooKeeper session id, possibly not connected to ZooKeeper?";
#vlog2 sprintf("session id: %s", $session_id);

$status = "OK";
if($null){
    $msg = "znode '$znode' exists";
} else {
    my $data = $zkh->get($znode, 'data_read_len' => 100);
                         #'stat' => $stat, 'watch' => $watch)
                         #|| quit "CRITICAL", "failed to read data from znode $znode: $!";
    defined($data) or quit "CRITICAL", "no data returned for znode '$znode' from zookeepers '$zookeepers': " . $zkh->get_error();
    # /hadoop-ha/logicaljt/ActiveStandbyElectorLock contains carriage returns which messes up the output in terminal by causing the second line to overwrite the first
    $data =~ s/\r//g;
    $data = trim($data);
    vlog3 "znode '$znode' data:\n\n$data\n";

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
            quit "CRITICAL", "znode '$znode' is empty!" . ( $verbose ? " (if this intentional supply -d \"\")" : "" );
        }
    }

    $msg = "retrieved znode '$znode' from zookeepers '$zookeepers'";
    $msg .= sprintf(", value='%s'", $data) if $verbose;
}

if($check_ephemeral){
    if($stat->{ephemeral_owner}){
        vlog2 "znode '$znode' is ephemeral";
    } else {
        quit "CRITICAL", "znode '$znode' is not ephemeral";
    }
}

if($check_child_znodes or $check_no_child_znodes){
    my @child_znodes = $zkh->get_children($znode);
    my $child_znode_num = scalar @child_znodes;
    vlog2 "checking for child znodes";
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

if(defined($stat)){
    my $mtime = $stat->{mtime} / 1000;
    isFloat($mtime) or quit "UNKNOWN", "invalid mtime returned for znode '$znode', got '$mtime'";
    vlog3 sprintf("znode '$znode' mtime = %s", $mtime);
    my $age_secs = time - int($mtime);
    vlog2 sprintf("znode mtime last modified %s secs ago", $age_secs);
    $msg .= sprintf(", last modified %s secs ago", $age_secs);
    check_thresholds($age_secs);
    if($age_secs < 0){
        my $clock_mismatch_msg = "clock synchronization problem, modified timestamp on znode is in the future! $msg";
        if($status eq "OK"){
            $msg = "$clock_mismatch_msg $msg";
        } else {
            $msg .= ". Also, $clock_mismatch_msg";
        }
        warning;
    }
} else {
    quit "UNKNOWN", "no stat object returned by ZooKeeper exists call for znode '$znode', try re-running with -vvvvD to see full debug output";
}

if($null){
    $msg .= ( $verbose ? " (--null specified, remaining checks skipped)" : "");
}

vlog2;
quit $status, $msg;
