#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-03-12 21:04:39 +0000 (Thu, 12 Mar 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check ZooKeeper ephemeral child znodes to check the number of live application workers, eg. for Solr -z /solr/live_nodes

Optional thresholds apply to the minimum number of child znodes to expect - this is to the number of worker nodes you expect to be alive.

Non-ephemeral znodes raises a warning by default as this will skew the purpose of the check which is supposed to be for live application workers where their znodes are only held as long as they stay in contact with the ZooKeeper. If really wanting to only check the number of child znodes and not care if they are really live node ephemeral znodes then use the --no-ephemeral-check switch.

Base off adjacent check_zookeeper_znode.pl (also part of the Advanced Nagios Plugins Collection)

Tested on Apache ZooKeeper 3.3.6, 3.4.5, 3.4.6, 3.4.8, 3.4.11 and on Hortonworks HDP 2.2.

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happens sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
";

$VERSION = "0.2";

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

my $MAX_LIST_NON_EPHEMERALS = 10;

my $znode;
my $no_ephemeral;

%options = (
    %zookeeper_options,
    "z|znode=s"          => [ \$znode,          "Znode parent to check for the number of child znodes" ],
    "no-ephemeral-check" => [ \$no_ephemeral,   "Do not enforce check that child znodes are ephemeral" ],
    %thresholdoptions,
);
@usage_order = qw/host port znode no-ephemeral-check user password warning critical random-conn-order session-timeout/;

get_options();

my @hosts = validate_hosts($host, $port);
$znode = validate_znode($znode);
validate_thresholds(0, 0, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1});

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

vlog2;
set_timeout();

$status = "OK";

connect_zookeepers(@hosts);

check_znode_exists($znode);

# we don't get a session id until after a call to the server such as exists() above
#my $session_id = $zkh->{session_id} or quit "UNKNOWN", "failed to determine ZooKeeper session id, possibly not connected to ZooKeeper?";
#vlog2 sprintf("session id: %s", $session_id);

vlog2 "checking for child znodes";
my @child_znodes = $zkh->get_children($znode);
@child_znodes = sort @child_znodes;
my $num_child_znodes = scalar @child_znodes;
vlog3 "$num_child_znodes child znodes detected" . ( @child_znodes ? ":\n\n" . join("\n", @child_znodes) . "\n" : "" );

plural $num_child_znodes;
$msg .= "$num_child_znodes child znode$plural found under '$znode'";
check_thresholds($num_child_znodes);

unless($no_ephemeral){
    my @non_ephemeral_znodes;
    foreach my $child_znode (@child_znodes){
        $child_znode = "$znode/$child_znode";
        $child_znode =~ s/\/{2,}/\//;
        # this checks for existence and populated zk_stat
        check_znode_exists($child_znode);
        if($zk_stat->{ephemeral_owner}){
            vlog2 "znode '$child_znode' is ephemeral";
        } else {
            push(@non_ephemeral_znodes, $child_znode);
        }
    }
    if(@non_ephemeral_znodes){
        my $num_non_ephemeral = scalar @non_ephemeral_znodes;
        warning;
        plural $num_non_ephemeral;
        $msg .= ", but $num_non_ephemeral non-ephemeral child znode$plural detected ";
        if($verbose){
            $msg .= "(";
            if($num_non_ephemeral > 10){
                for(my $i=0; $i < 10; $i++){
                    $msg .= $non_ephemeral_znodes[$i] . ", ";
                }
            } else {
                $msg .= join(", ", @non_ephemeral_znodes);
            }
            $msg .= ")";
        }
    }
}

$msg .= " | num_child_znodes=$num_child_znodes";
msg_perf_thresholds(0, 1);

vlog2;
quit $status, $msg;
