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

$DESCRIPTION = "Nagios Plugin to check SolrCloud cluster state, specifically collection shards and replicas, via ZooKeeper contents

See also check_solrcloud_server_znode.pl to check individual Solr server ephemeral znodes

Tested on ZooKeeper 3.4.5 and 3.4.6 with SolrCloud 4.x

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr - ie this will occur if you supply the incorrect base znode and it happens to be null
";

$VERSION = "0.1";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    use lib "/usr/local/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr qw/validate_solr_collection/;
use HariSekhon::ZooKeeper;
use Net::ZooKeeper qw/:DEFAULT :errors :log_levels/;

# Max num of chars to read from znode contents
$DATA_READ_LEN = 50000;
#my $max_age = 600; # secs

my $znode = "clusterstate.json";
my $base = "/solr";

my $collection;
my $no_warn_replicas;
my $show_settings;
my $list_collections;

env_vars("SOLR_COLLECTION", \$collection);

%options = (
    %zookeeper_options,
    "b|base=s"         => [ \$base,             "Base Znode for Solr in ZooKeeper (default: /solr, should be just / for embedded or non-chrooted zookeeper)" ],
    "C|collection=s"   => [ \$collection,       "Solr Collection to check (defaults to all if not specified, \$SOLR_COLLECTION)" ],
    "no-warn-replicas" => [ \$no_warn_replicas, "Do not warn on down replicas (only check for shards being up/down)" ],
    "show-settings"    => [ \$show_settings,    "Show collection shard/replication settings" ],
    "list-collections" => [ \$list_collections, "List Solr Collections and exit" ],
    #"a|max-age=s" =>  [ \$max_age,    "Max age of the clusterstate znode information in seconds (default: 600)" ],
);
@usage_order = qw/host port user password collection base no-warn-replicas show-settings max-age random-conn-order session-timeout list-collections/;

get_options();

my @hosts   = validate_hosts($host, $port);
$znode      = validate_filename($base, 0, "base znode") . "/$znode";
$znode      =~ s/\/+/\//g;
$znode      = validate_filename($znode, 0, "clusterstate znode");
$collection = validate_solr_collection($collection) if $collection;
#validate_thresholds(0, 1, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1}, "max znode age", $max_age);

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

$zk_timeout = validate_float($zk_timeout, "zookeeper session timeout", 0.001, 100);

vlog2;
set_timeout();

$status = "OK";

$zk_timeout *= 1000;

my $zkh = connect_zookeepers(@hosts);

check_znode_exists($zkh, $znode);

# we don't get a session id until after a call to the server such as exists() above
#my $session_id = $zkh->{session_id} or quit "UNKNOWN", "failed to determine ZooKeeper session id, possibly not connected to ZooKeeper?";
#vlog2 sprintf("session id: %s", $session_id);

my $data = $zkh->get($znode, 'data_read_len' => $DATA_READ_LEN);
                     #'stat' => $zk_stat, 'watch' => $watch)
                     #|| quit "CRITICAL", "failed to read data from znode $znode: $!";
defined($data) or quit "CRITICAL", "no data returned for znode '$znode' from zookeeper$plural '@hosts': " . $zkh->get_error();
# /hadoop-ha/logicaljt/ActiveStandbyElectorLock contains carriage returns which messes up the output in terminal by causing the second line to overwrite the first
$data =~ s/\r//g;
$data = trim($data);
vlog3 "znode '$znode' data:\n\n$data\n";
$data = isJson($data) or quit "CRITICAL", "znode '$znode' data is not json as expected, got '$data'";

unless(scalar keys %$data){
    quit "CRITICAL", "no collections found in cluster state in zookeeper";
}

if($list_collections){
    print "Solr Collections:\n\n";
    foreach(sort keys %$data){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my %inactive_shards;
#my %inactive_shard_states;
my %inactive_replicas;
#my %inactive_replica_states;
my %inactive_replicas_active_shards;
my %facts;

sub check_collection($){
    my $collection = shift;
    vlog2 "collection '$collection': ";
    my %shards = get_field2_hash($data, "$collection.shards");
    foreach my $shard (sort keys %shards){
        my $state = get_field2($data, "$collection.shards.$shard.state");
        vlog2 "\t\t\tshard '$shard' state '$state'";
        unless($state eq "active"){
            $inactive_shards{$collection}{$shard} = $state;
            #push(@{$inactive_shard_states{$collection}{$state}}, $shard);
        }
        my %replicas = get_field2_hash($data, "$collection.shards.$shard.replicas");
        foreach my $replica (sort keys %replicas){
            my $replica_name  = get_field2($data, "$collection.shards.$shard.replicas.$replica.node_name");
            my $replica_state = get_field2($data, "$collection.shards.$shard.replicas.$replica.state");
            $replica_name =~ s/_solr$//;
            vlog2 "\t\t\t\t\treplica '$replica_name' state '$replica_state'";
            unless($replica_state eq "active"){
                $inactive_replicas{$collection}{$shard}{$replica_name} = $replica_state;
                #push(@{$inactive_replica_states{$collection}{$shard}{$replica_state}}, $replica_name);
                if($state eq "active"){
                    $inactive_replicas_active_shards{$collection}{$shard}{$replica_name} = $replica_state;
                }
            }
        }
    }
    $facts{$collection}{"maxShardsPerNode"}  = get_field2_int($data, "$collection.maxShardsPerNode");
    $facts{$collection}{"router"}            = get_field2($data,     "$collection.router.name");
    $facts{$collection}{"replicationFactor"} = get_field2_int($data, "$collection.replicationFactor");
    $facts{$collection}{"autoAddReplicas"}   = get_field2($data,     "$collection.autoAddReplicas");
    vlog2;
}

my $found = 0;
foreach(keys %$data){
    if($collection){
        if($collection eq $_){
            $found++;
            check_collection($_);
        }
    } else {
        check_collection($_);
    }
}
if($collection and not $found){
    quit "CRITICAL", "collection '$collection' not found, did you specify the correct name? See --list-collections for list of known collections";
}

if(%inactive_shards){
    critical;
    $msg = "SolrCloud shards down: ";
    # Initially used inverted index hashes to display uniquely all the different shard states, but then when extending to replica states this really became too much, simpler to just call shards and replicas 'down' if not active
    foreach my $collection (sort keys %inactive_shards){
        my $num_inactive = scalar keys(%{$inactive_shards{$collection}});
        plural $num_inactive;
        $msg .= "collection '$collection' => $num_inactive shard$plural down";
        if($verbose){
            $msg .= " (";
            foreach my $shard (sort keys %{$inactive_shards{$collection}}){
                $msg .= "$shard,";
                #foreach my $replica_name (sort keys %{$inactive_replicas{$collection}{$shard}}){
                    #$msg .= " (" . join(",", @{$inactive_replica_states{$collection}{$state}}) . "), ";
                #}
            }
            $msg =~ s/,$/)/;
        }
        $msg .= ", ";
    }
    $msg =~ s/, $//;
    unless($no_warn_replicas){
        if(%inactive_replicas_active_shards){
            $msg .= ". Additional backup shard replicas down (shards still up): ";
            foreach my $collection (sort keys %inactive_replicas_active_shards){
                $msg .= "collection '$collection' ";
                foreach my $shard (sort keys %{$inactive_replicas_active_shards{$collection}}){
                    $msg .= "shard '$shard'";
                    if($verbose){
                        $msg .= " (" . join(",", sort keys %{$inactive_replicas_active_shards{$collection}{$shard}}) . ")";
                    }
                    $msg .= ", ";
                }
                $msg =~ s/, $//;
            }
            $msg =~ s/, $//;
        }
    }
} elsif(%inactive_replicas and not $no_warn_replicas){
    warning;
    $msg = "SolrCloud shard replicas down: ";
    foreach my $collection (sort keys %inactive_replicas){
        $msg .= "collection '$collection' ";
        foreach my $shard (sort keys %{$inactive_replicas{$collection}}){
            $msg .= "shard '$shard'";
            if($verbose){
                $msg .= " (" . join(",", sort keys %{$inactive_replicas{$collection}{$shard}}) . ")";
            }
            $msg .= ", ";
        }
        $msg =~ s/, $//;
    }
    $msg =~ s/, $//;
} else {
    my $collections;
    if($collection){
        $plural = "";
        $collections = $collection;
    } else {
        plural keys %$data;
        $collections = join(", ", sort keys %$data);
    }
    $msg = "all SolrCloud shards " . ( $no_warn_replicas ? "" : "and replicas " ) . "active for collection$plural: $collections";
}

if($show_settings){
    $msg .= ". Replication Settings: ";
    foreach my $collection (sort keys %facts){
        $msg .= "collection '$collection'";
        foreach(qw/maxShardsPerNode router replicationFactor autoAddReplicas/){
            $msg .= " $_=" . $facts{$collection}{$_};
        }
        $msg .= ", ";
    }
    $msg =~ s/, $//;
}

if(defined($zk_stat)){
    my $mtime = $zk_stat->{mtime} / 1000;
    isFloat($mtime) or quit "UNKNOWN", "invalid mtime returned for znode '$znode', got '$mtime'";
    vlog3 sprintf("znode '$znode' mtime = %s", $mtime);
    my $age_secs = time - int($mtime);
    vlog2 "cluster state last modified $age_secs secs ago";
    $msg .= sprintf(". Cluster state last modified %s ago", sec2human($age_secs));
    #check_thresholds($age_secs, 0, "max znode age");
    if($age_secs < 0){
        my $clock_mismatch_msg = "clock synchronization problem, modified timestamp on znode is in the future!";
        if($status eq "OK"){
            $msg = "$clock_mismatch_msg $msg";
        } else {
            $msg .= ". Also, $clock_mismatch_msg";
        }
        warning;
    }
    $msg .= " | cluster_state_last_changed=${age_secs}s";
} else {
    quit "UNKNOWN", "no stat object returned by ZooKeeper exists call for znode '$znode', try re-running with -vvvvD to see full debug output";
}

vlog2;
quit $status, $msg;
