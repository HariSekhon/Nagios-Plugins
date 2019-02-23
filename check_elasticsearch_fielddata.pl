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

$DESCRIPTION = "Nagios Plugin to check the volume of fielddata for a given Elasticsearch node

Optional --warning/--critical threshold ranges may be applied to the volume in bytes

Also outputs total fielddata on all nodes

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.5.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $node;
my $list_nodes;

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    "N|node=s"    => [ \$node,       "Node hostname or IP address of node for which to check fielddata volume" ],
    "list-nodes"  => [ \$list_nodes, "List nodes (this API no longer returns nodes without fielddata from 5.0 onwards, use --list from one of the adjacent plugins instead)" ],
    %thresholdoptions,
);
push(@usage_order, qw/node list-nodes/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
unless($list_nodes){
    defined($node) or usage "node not defined, see --list-nodes to see which nodes are available to specify";
    $node = (isIP($node) or isHostname($node)) or usage "invalid node specified, must be IP or hostname of node according to --list-nodes";
    vlog_option "node", $node;
}
validate_thresholds(0, 0);

vlog2;
set_timeout();

$status = "OK";

my $url = "/_cat/fielddata?h=host,ip,total&bytes=b";
my $content = curl_elasticsearch_raw $url;

my @parts;
my $node_hostname;
my $ip;
my $bytes;
my $total = 0;
my $found = 0;
if($list_nodes or $verbose >= 2){
    print "Nodes:\n\n" if $list_nodes;
    printf "%-35s\t%s\n", "Hostname", "IP";
}
my ($this_name, $this_ip, $this_bytes);
foreach(split(/\n/, $content)){
    @parts = split(/\s+/, $_);
    defined($parts[2])    or quit "UNKNOWN", "failed to find 3rd field in result. $nagios_plugins_support_msg_api";
    isHost($parts[0])     or quit "UNKNOWN", "invalid host returned for 1st field in result. $nagios_plugins_support_msg_api";
    isIP($parts[1])       or quit "UNKNOWN", "returned non-IP for 1st field in result. $nagios_plugins_support_msg_api";
    isInt($parts[2])      or quit "UNKNOWN", "returned non-integer for 2nd field in result. $nagios_plugins_support_msg_api";
    $this_name  = $parts[0];
    $this_ip    = $parts[1];
    $this_bytes = $parts[2];
    if($list_nodes or $verbose >= 2){
        printf "%-35s\t%s\n", $this_name, $this_ip;
        next;
    }
    $total += $this_bytes;
    next if $found;
    if($node eq $this_ip or $node eq $this_name){
        $node_hostname = $this_name;
        $ip    = $this_ip;
        $bytes = $this_bytes;
        vlog2 "found node $node, node hostname = $node_hostname, ip = $ip";
        $found = 1;
    }
}
exit $ERRORS{"UNKNOWN"} if($list_nodes);

# Elasticsearch 5.0 changed the behaviour to no output if there is no perfdata instead of listing 0b :-/
if(defined($bytes)){
    if(defined($ip) or defined($node_hostname)) {
        if (defined($ip) and $node eq $ip) {
        } elsif (defined($node_hostname) and $node eq $node_hostname) {
        } else {
            quit "UNKNOWN", "failed to find matching node '$node' in result from Elasticsearch";
        }
    }
} else {
    vlog2 "node not found in output, probably Elasticsearch 5.0+ which stopped outputting lines for 0 bytes, inferring 0 bytes";
    $bytes = 0;
}

unless(defined($node_hostname)){
    $node_hostname = $node;
}

$msg = "elasticsearch ";

$msg .= "fielddata on node '$node_hostname'";
$msg .= " ($ip)" if ($verbose and defined($ip));
$msg .= " = " . human_units($bytes);
check_thresholds($bytes);
$msg .= ", total fielddata on all nodes = " . human_units($total);
$msg .= " | node_fielddata=${bytes}b";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
