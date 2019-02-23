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

$DESCRIPTION = "Nagios Plugin to check the disk % space used on a given Elasticsearch node in a cluster

Will test the first node with matching hostname/FQDN/IP or Elasticsearch node name. Client nodes like LogStash will not be counted as they don't expose disk % but if co-locating more than one Elasticsearch data node instance on a host you should supply the Elasticsearch node instance name instead to be more specific otherwise you will only be able to test the first instance found (--list-nodes shows all available hosts/IP and instance names).

For regular deployments with one Elasticsearch instance per server it's perfectly fine to just specify the IP or the hostname/FQDN for convenience.

For convenience --node defaults to same as --host, which may not match if you're specifying a short hostname for --host and elasticsearch is reporting an FQDN, in which case you should specify the node explicitly as shown by the output of --list-nodes.

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

set_threshold_defaults(75, 90);

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
    #defined($node) or usage "node not defined, see --list-nodes";
    unless(defined($node)){
        $node = $host;
    }
    $node =~ /^([\w\s\._-]+)$/ or usage "invalid node name specified, must be alphanumeric, may contain spaces, dashes, underscores and dots";
    $node = $1;
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 0, 'positive' => 1, 'min' => 0, 'max' => 100 });

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_nodes();

# This looks like it's fields might have changed in 1.6
my $url = "/_cat/allocation?h=disk.percent,host,ip,node";
$url .= "&v" if $verbose > 2;
my $content = curl_elasticsearch_raw $url;

# the last node name may contain spaces
my $regex = qr/^\s*(\d+(?:\.\d+)?)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;
my $regex_nodisk = qr/^\s+\S+\s+\S+\s+.+?\s*$/;

my $disk;
my $node_host;
my $node_name;
my $ip;
foreach my $line (split(/\n/, $content)){
    #vlog3 "line: $line";
    if($line =~ $regex){
        my $disk2  = $1;
        $node_host = $2;
        $ip        = $3;
        $node_name = $4;
        if($node_name eq $node or $node_host eq $node or $ip eq $node){
            $disk = $disk2;
            last;
        }
    } elsif($line =~ $regex_nodisk){
        # LogStash, skip
    } elsif($line =~ /^\s*disk.percent\s+host\s+ip\s+node\s*$/){
    } elsif($line =~ /^\s*UNASSIGNED\s*$/){
    } elsif($line =~ /^\s*$/){
    } else {
        quit "UNKNOWN", "unrecognized output from Elasticsearch API detected! $nagios_plugins_support_msg_api. Offending line was '$line'";
    }
}

unless(defined($disk)){
    quit "UNKNOWN", "no disk % found for node '$node', did you specify correct node? See --list-nodes";
}

$msg  = sprintf("Elasticsearch node disk = %.2f%%", $disk);
check_thresholds($disk);
$msg .= sprintf(" for node host '%s' name '%s'", $node_host, $node_name) if $verbose;
$msg .= " | 'disk %'=$disk%";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
