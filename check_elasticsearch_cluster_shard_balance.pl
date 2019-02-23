#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-03-21 16:53:17 +0000 (Sat, 21 Mar 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

# https://www.elastic.co/guide/en/elasticsearch/reference/current/cat-allocation.html

# forked from check_elasticsearch_node_stats.pl

$DESCRIPTION = "Nagios Plugin to check max shard imbalance in number of shards between Elasticsearch nodes in a cluster

In order to account for client nodes like co-located LogStash this code ignores nodes with 0 shards (see check_elasticsearch_node_shards.pl to cover that which automatically alerts warning on on 0 shard nodes).

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(30, 200);

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 0, 'positive' => 1});

vlog2;
set_timeout();

$status = "OK";

# This looks like it's fields might have changed in 1.6
my $url = "/_cat/allocation?h=shards,host,ip,node";
$url .= "&v" if $verbose > 2;
my $content = curl_elasticsearch_raw $url;

# the last node name may contain spaces
my $regex = qr/^\s*(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;

my %shards_by_nodename;
my $unassigned_shards;
my %hosts;
my $num_nodes = 0;
foreach my $line (split(/\n/, $content)){
    #vlog3 "line: $line";
    if($line =~ $regex){
        my $shards    = $1;
        my $node_host = $2;
        my $ip        = $3;
        my $node_name = $4;
        next if $shards == 0;
        $num_nodes++;
        $shards_by_nodename{$node_name}{"shards"}    = $shards;
        $shards_by_nodename{$node_name}{"node_host"} = $node_host;
        $shards_by_nodename{$node_name}{"ip"}        = $ip;
        $hosts{$node_host} = 1;
    } elsif($line =~ /^\s*shards\s+host\s+ip\s+node\s*$/){
    } elsif($line =~ /^\s*(\d+)\s+UNASSIGNED\s*$/){
        # use the other existing elasticsearch plugins adjacent to this one to check for unassigned shards
        $unassigned_shards = $1;
    } elsif($line =~ /^\s*$/){
    } else {
        quit "UNKNOWN", "unrecognized output from Elasticsearch API detected! $nagios_plugins_support_msg_api";
    }
}

if($num_nodes == 0){
    quit "UNKNOWN", "no nodes found with shards";
}

my $num_hosts = scalar keys %hosts;

my $min_shards;
my $max_shards;
my $min_shards_hostname;
my $min_shards_nodename;
my $max_shards_hostname;
my $max_shards_nodename;
foreach my $node_name (sort keys %shards_by_nodename){
    my $shards = $shards_by_nodename{$node_name}{"shards"};
    # do not count nodes with zero shards as they're likely client nodes like LogStash, check_elasticsearch_node_shards.pl will detect if nodes we expect to have shards have zero shards
    if( ( ( not defined($min_shards) ) or $shards < $min_shards ) and $shards != 0 ){
        $min_shards = $shards;
        $min_shards_nodename = $node_name;
        $min_shards_hostname = $shards_by_nodename{$node_name}{"node_host"};
    }
    if( ( not defined($max_shards) ) or $shards > $max_shards ){
        $max_shards = $shards;
        $max_shards_nodename = $node_name;
        $max_shards_hostname = $shards_by_nodename{$node_name}{"node_host"};
    }
}
unless(defined($min_shards)){
    quit "UNKNOWN", "min shards not found, did you run this against empty elasticsearch node(s)?";
}
unless($min_shards > 0){
    quit "UNKNOWN", "min shards = 0, did you run this against empty elasticsearch node(s)?";
}
unless(
    defined($max_shards) and
    defined($min_shards_hostname) and
    defined($max_shards_hostname) and
    defined($min_shards_nodename) and
    defined($max_shards_nodename)
   ){
   quit "UNKNOWN", "failed to determine details for min/max shards/hostname/nodename. $nagios_plugins_support_msg";
}

# protect against divide by zero
my $divisor = $min_shards || 1;

my $max_shard_imbalance = ( $max_shards - $min_shards ) / $divisor * 100;

$max_shard_imbalance = sprintf("%.2f", $max_shard_imbalance);

plural $num_nodes;
$msg  = sprintf("Elasticsearch max shard imbalance = %.2f%%", $max_shard_imbalance);
check_thresholds($max_shard_imbalance);
$msg .= sprintf(" between %d node%s", $num_nodes, $plural);
plural $num_hosts;
$msg .= sprintf(" on %d host%s", $num_hosts, $plural);
if($unassigned_shards){
    $msg .= " [$unassigned_shards UNASSIGNED SHARDS]";
}
if($verbose){
    $msg .= " (min shards = $min_shards on host '$min_shards_hostname' name '$min_shards_nodename', max shards = $max_shards on host '$max_shards_hostname' name '$max_shards_nodename')";
}
$msg .= " | max_shard_imbalance=$max_shard_imbalance%";
msg_perf_thresholds();
$msg .= " data_nodes=$num_nodes hosts=$num_hosts";

vlog2;
quit $status, $msg;
