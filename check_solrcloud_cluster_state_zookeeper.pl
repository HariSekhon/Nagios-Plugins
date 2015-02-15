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

Checks:

For a given SolrCloud Collection or all collections found if --collection is not specified:

1. Checks there is at least one collection found
2. Checks each shard of the collection is 'active'
3. Checks each shard of the collection has at least one active replica
4. Checks each shard for any down backup replicas (can be optionally disabled)
5. Optionally shows replication settings per collection
6. Returns time since last cluster state change in both human form and perfdata secs for graphing

See also adjacent plugins:

check_solrcloud_server_znode.pl         - checks individual Solr server ephemeral znodes
check_solrcloud_live_nodes_zookeeper.pl - checks thresholds on number of live SolrCloud nodes

Tested on ZooKeeper 3.4.5 and 3.4.6 with SolrCloud 4.x

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. API segfaults if you try to check the contents of a null znode such as those kept by SolrCloud servers eg. /solr/live_nodes/<hostname>:8983_solr - ie this will occur if you supply the incorrect base znode and it happens to be null
";

$VERSION = "0.3";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    use lib "/usr/local/lib";
}
use HariSekhonUtils;
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
    "no-warn-replicas" => [ \$no_warn_replicas, "Do not warn on down backup replicas (only check for shards being active and having at least one active replica)" ],
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

vlog2;
set_timeout();

$status = "OK";

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
my %shards_without_active_replicas;
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
        my $found_active_replica = 0;
        foreach my $replica (sort keys %replicas){
            my $replica_name  = get_field2($data, "$collection.shards.$shard.replicas.$replica.node_name");
            my $replica_state = get_field2($data, "$collection.shards.$shard.replicas.$replica.state");
            $replica_name =~ s/_solr$//;
            vlog2 "\t\t\t\t\treplica '$replica_name' state '$replica_state'";
            if($replica_state eq "active"){
                $found_active_replica++;
            } else {
                $inactive_replicas{$collection}{$shard}{$replica_name} = $replica_state;
                #push(@{$inactive_replica_states{$collection}{$shard}{$replica_state}}, $replica_name);
                if($state eq "active"){
                    $inactive_replicas_active_shards{$collection}{$shard}{$replica_name} = $replica_state;
                }
            }
        }
        if(not $found_active_replica and not defined($inactive_shards{$collection}{$shard})){
            $shards_without_active_replicas{$collection}{$shard} = $state;
            delete $inactive_replicas_active_shards{$collection}{$shard};
            delete $inactive_replicas_active_shards{$collection} unless %{$inactive_replicas_active_shards{$collection}};
        }
    }
    if(not defined(%{$inactive_shards{$collection}})){
        delete $inactive_shards{$collection};
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

sub msg_replicas_down($){
    my $hashref = shift;
    foreach my $collection (sort keys %$hashref){
        $msg .= "collection '$collection' ";
        foreach my $shard (sort keys %{$$hashref{$collection}}){
            $msg .= "shard '$shard'";
            if($verbose){
                $msg .= " (" . join(",", sort keys %{$$hashref{$collection}{$shard}}) . ")";
            }
            $msg .= ", ";
        }
        $msg =~ s/, $//;
    }
    $msg =~ s/, $//;
}

sub msg_additional_replicas_down(){
    unless($no_warn_replicas){
        if(%inactive_replicas_active_shards){
            $msg .= ". Additional backup shard replicas down (shards still up): ";
            msg_replicas_down(\%inactive_replicas_active_shards);
        }
    }
}

sub msg_shards($){
    my $hashref = shift;
    foreach my $collection (sort keys %$hashref){
        my $num_inactive = scalar keys(%{$$hashref{$collection}});
        plural $num_inactive;
        #next unless $num_inactive > 0;
        $msg .= "collection '$collection' => $num_inactive shard$plural down";
        if($verbose){
            $msg .= " (";
            foreach my $shard (sort keys %{$$hashref{$collection}}){
                $msg .= "$shard,";
            }
            $msg =~ s/,$//;
        }
        $msg .= "), ";
    }
    $msg =~ s/, $//;
}

# Initially used inverted index hashes to display uniquely all the different shard states, but then when extending to replica states this really became too much, simpler to just call shards and replicas 'down' if not active
if(%inactive_shards){
    critical;
    $msg = "SolrCloud shards down: ";
    msg_shards(\%inactive_shards);
    if(%shards_without_active_replicas){
        $msg .= ". SolrCloud shards 'active' but with no active replicas: ";
        msg_shards(\%shards_without_active_replicas);
    }
    msg_additional_replicas_down();
} elsif(%shards_without_active_replicas){
    critical;
    $msg = "SolrCloud shards 'active' but with no active replicas: ";
    msg_shards(\%shards_without_active_replicas);
    msg_additional_replicas_down();
} elsif(%inactive_replicas and not $no_warn_replicas){
    warning;
    $msg = "SolrCloud shard replicas down: ";
    msg_replicas_down(\%inactive_replicas);
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

get_znode_age($znode);
$msg .= " | cluster_state_last_changed=${znode_age_secs}s";

vlog2;
quit $status, $msg;
