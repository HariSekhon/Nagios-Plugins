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

$DESCRIPTION = "Nagios Plugin to check the number of shards assigned to a given Elasticsearch node in a cluster

Should specify an Elasticsearch node name rather than a hostname/FQDN/IP (see --list-nodes), as sometimes hosts may have more than once instance or client nodes like logstash-<fqdn>-<\\d+>-<\\d+> which also share the same hostname/FQDN and will result in multiple ambiguous matches, resulting in an UNKNOWN error condition to flag for user to correct this and be more specific.

Tested on Elasticsearch 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

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

set_threshold_defaults("1:", 10000);

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %elasticsearch_node,
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
# this is the node name, not using validate_host because an IP returns logstash clients and don't want to have to deal with that
#$node  = validate_hostname($node, "node") unless $list_nodes;
# hostname is too restrictive because of default Marvel names, and in some cases we may want to just do it by IP or hostname or whatever as long as there are not more than one colocated node (including client nodes like LogStash) on the same hosts
unless($list_nodes){
    defined($node) or usage "node not defined, see --list-nodes";
    $node =~ /^([\w\s\._-]+)$/ or usage "invalid node name specified, must be alphanumeric, may contain spaces, dashes, underscores and dots";
    $node = $1;
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 1, 'positive' => 0});

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_nodes();

# This looks like it's fields might have changed in 1.6
my $url = "/_cat/allocation?h=shards,host,ip,node";
$url .= "&v" if $verbose > 2;
my $content = curl_elasticsearch_raw $url;

my $regex = qr/^\s*(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;

my $nodename;
my $nodehost;
my $ip;
my $shards;
my %shards_by_hostname;
my %shards_by_nodename;
my %shards_by_ip;
foreach my $line (split(/\n/, $content)){
    #vlog3 "line: $line";
    if($line =~ $regex){
        my $shards    = $1;
        my $node_host = $2;
        my $ip        = $3;
        my $node_name = $4;
        $shards_by_nodename{$node_name}{"shards"}    = $shards;
        $shards_by_nodename{$node_name}{"node_host"} = $node_host;
        $shards_by_nodename{$node_name}{"ip"}        = $ip;
        $shards_by_hostname{$node_host}{$node_name}{"shards"} = $shards;
        $shards_by_hostname{$node_host}{$node_name}{"ip"}     = $ip;
        $shards_by_ip{$ip}{$node_name}{"shards"}    = $shards;
        $shards_by_ip{$ip}{$node_name}{"node_host"} = $node_host;
    } elsif($line =~ /^\s*shards\s+host\s+ip\s+node\s*$/){
    } elsif($line =~ /^\s*\d+\s+UNASSIGNED\s*$/){
        # use the other existing elasticsearch plugins adjacent to this one to check for unassigned shards
    } elsif($line =~ /^\s*$/){
    } else {
        quit "UNKNOWN", "unrecognized output from Elasticsearch API detected! $nagios_plugins_support_msg_api";
    }
}
foreach my $node_name (sort keys %shards_by_nodename){
    if($node_name eq $node){
        $shards   = $shards_by_nodename{$node_name}{"shards"};
        $nodehost = $shards_by_nodename{$node_name}{"node_host"};
        $nodename = $node_name;
        last;
    }
}
unless(defined($shards)){
    foreach my $node_host (sort keys %shards_by_hostname){
        if($node_host eq $node){
            if(scalar keys %{$shards_by_hostname{$node_host}} > 1){
                quit "UNKNOWN", "multiple nodes with hostname '$node_host', must specify the more unique node name, see --list-nodes";
            }
            foreach my $node_name (keys %{$shards_by_hostname{$node_host}}){
                $shards   = $shards_by_hostname{$node_host}{$node_name}{"shards"};
                $nodename = $node_name;
                $nodehost = $node_host;
                last;
            }
        }
    }
}
unless(defined($shards)){
    foreach my $ip (sort keys %shards_by_ip){
        if($ip eq $node){
            if(scalar keys %{$shards_by_ip{$ip}} > 1){
                quit "UNKNOWN", "multiple nodes with ip '$ip', must specify the more unique node name, see --list-nodes";
            }
            foreach my $node_name (keys %{$shards_by_ip{$ip}}){
                $shards   = $shards_by_ip{$ip}{$node_name}{"shards"};
                $nodename = $node_name;
                $nodehost = $shards_by_ip{$ip}{$node_name}{"node_host"};
                last;
            }
        }
    }
}
defined($shards) or quit "UNKNOWN", "failed to determine number of shards for node '$node'. Did you specify the correct node name? See --list-nodes";

plural $shards;
$msg = "Elasticsearch node host '$nodehost' name '$nodename' has $shards shard$plural";
check_thresholds($shards);
$msg .= " | node_shards=$shards";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
