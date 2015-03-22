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

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $node_ip;
my $list_node_ips;

%options = (
    %hostoptions,
    "I|node-ip=s"   => [ \$node_ip,       "IP address of node for which to check fielddata volume" ],
    "list-node-ips" => [ \$list_node_ips, "List node IPs" ],
    %thresholdoptions,
);
push(@usage_order, qw/node-ip list-node-ips/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$node_ip = validate_ip($node_ip, "node") unless $list_node_ips;
validate_thresholds(0, 0);

vlog2;
set_timeout();

$status = "OK";

my $url = "/_cat/fielddata?h=ip,total&bytes=b";
my $content = curl_elasticsearch_raw $url;

my @parts;
my $ip;
my $bytes;
print "Node IPs:\n\n" if $list_node_ips;
foreach(split(/\n/, $content)){
    @parts = split(/\s+/, $content);
    defined($parts[1]) or quit "UNKNOWN", "failed to find 2nd field in result. $nagios_plugins_support_msg_api";
    isIP($parts[0]) or quit "UNKNOWN", "returned non-IP for 1st field in result. $nagios_plugins_support_msg_api";
    $ip = $parts[0];
    if($list_node_ips){
        print "$ip\n";
        next;
    }
    if($ip eq $node_ip){
        isInt($parts[1]) or quit "UNKNOWN", "returned non-integer for 2nd field in result. $nagios_plugins_support_msg_api";
        $bytes = $parts[1];
    }
}
exit $ERRORS{"UNKNOWN"} if($list_node_ips);

$ip eq $node_ip or quit "UNKNOWN", "failed to find node with IP '$node_ip' in result from Elasticsearch";

$msg = "elasticsearch ";

$msg .= "total fielddata on node '$node_ip' = " . human_units($bytes);
check_thresholds($bytes);

$msg .= " | total_fielddata=$bytes";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
