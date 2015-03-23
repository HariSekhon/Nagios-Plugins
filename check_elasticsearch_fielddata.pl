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

Tested on Elasticsearch 1.2.1 and 1.4.4";

$VERSION = "0.2.1";

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
    "N|node=s"    => [ \$node,       "Node hostname or IP address of node for which to check fielddata volume" ],
    "list-nodes"  => [ \$list_nodes, "List nodes" ],
    %thresholdoptions,
);
push(@usage_order, qw/node list-nodes/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
unless($list_nodes){
    defined($node) or usage "node not defined, see --list-nodes to see which nodes are available to specify";
    $node = (isIP($node) or isHostname($node)) or usage "invalid node specified, must be IP or hostname of node according to --list-nodes";
    vlog_options "node", $node;
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
print "Nodes:\n\n" if $list_nodes;
foreach(split(/\n/, $content)){
    @parts = split(/\s+/, $_);
    defined($parts[2]) or quit "UNKNOWN", "failed to find 3rd field in result. $nagios_plugins_support_msg_api";
    isIP($parts[1]) or quit "UNKNOWN", "returned non-IP for 1st field in result. $nagios_plugins_support_msg_api";
    $ip = $parts[1];
    isHostname($parts[0]) or quit "UNKNOWN", "invalid hostname returned for 1st field in result. $nagios_plugins_support_msg_api";
    $node_hostname = $parts[0];
    if($list_nodes){
        print "$node_hostname\t$ip\n";
        next;
    }
    if($node eq $ip or $node eq $node_hostname){
        isInt($parts[2]) or quit "UNKNOWN", "returned non-integer for 2nd field in result. $nagios_plugins_support_msg_api";
        $bytes = $parts[2];
        last;
    }
}
exit $ERRORS{"UNKNOWN"} if($list_nodes);

($node eq $ip or $node eq $node_hostname) or quit "UNKNOWN", "failed to find node '$node' in result from Elasticsearch";

$msg = "elasticsearch ";

$msg .= "total fielddata on node '$node_hostname'";
$msg .= " ($ip)" if $verbose;
$msg .= " = " . human_units($bytes);
check_thresholds($bytes);

$msg .= " | total_fielddata=${bytes}b";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
