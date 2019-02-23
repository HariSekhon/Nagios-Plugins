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

$DESCRIPTION = "Nagios Plugin to check the difference in max disk % space used between Elasticsearch nodes in a cluster

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

set_threshold_defaults(20, 80);

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
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 0, 'positive' => 1, 'min' => 0, 'max' => 100 });

vlog2;
set_timeout();

$status = "OK";

# This looks like it's fields might have changed in 1.6
my $url = "/_cat/allocation?h=disk.percent,host,ip,node";
$url .= "&v" if $verbose > 2;
my $content = curl_elasticsearch_raw $url;

# the last node name may contain spaces
my $regex = qr/^\s*(\d+)\s+(\S+)\s+(\S+)\s+(.+?)\s*$/;
my $regex_nodisk = qr/^\s+\S+\s+\S+\s+.+?\s*$/;

my %disk_by_nodename;
my %hosts;
my $num_nodes = 0;
foreach my $line (split(/\n/, $content)){
    #vlog3 "line: $line";
    if($line =~ $regex){
        my $disk      = $1;
        my $node_host = $2;
        my $ip        = $3;
        my $node_name = $4;
        # client nodes like LogStash have blank not zero
        #next if $disk == 0;
        $num_nodes++;
        $disk_by_nodename{$node_name}{"disk"}      = $disk;
        $disk_by_nodename{$node_name}{"node_host"} = $node_host;
        $disk_by_nodename{$node_name}{"ip"}        = $ip;
        $hosts{$node_host} = 1;
    } elsif($line =~ $regex_nodisk){
        # LogStash, skip
    } elsif($line =~ /^\s*disk.percent\s+host\s+ip\s+node\s*$/){
    } elsif($line =~ /^\s*UNASSIGNED\s*$/){
    } elsif($line =~ /^\s*$/){
    } else {
        quit "UNKNOWN", "unrecognized output from Elasticsearch API detected! $nagios_plugins_support_msg_api. Offending line was '$line'";
    }
}

if($num_nodes == 0){
    quit "UNKNOWN", "no nodes found with disk %";
}

my $num_hosts = scalar keys %hosts;

my $min_disk;
my $max_disk;
my $min_disk_hostname;
my $min_disk_nodename;
my $max_disk_hostname;
my $max_disk_nodename;
foreach my $node_name (sort keys %disk_by_nodename){
    my $disk = $disk_by_nodename{$node_name}{"disk"};
    # do not count nodes with zero disk as they're likely client nodes like LogStash, check_elasticsearch_node_disk.pl will detect if nodes we expect to have disk have zero disk
    if( ( ( not defined($min_disk) ) or $disk < $min_disk ) and $disk != 0 ){
        $min_disk = $disk;
        $min_disk_nodename = $node_name;
        $min_disk_hostname = $disk_by_nodename{$node_name}{"node_host"};
    }
    if( ( ( not defined($max_disk) ) or $disk > $max_disk ) and $disk != 0 ){
        $max_disk = $disk;
        $max_disk_nodename = $node_name;
        $max_disk_hostname = $disk_by_nodename{$node_name}{"node_host"};
    }
}
unless(defined($min_disk)){
    quit "UNKNOWN", "min disk not found, did you run this against empty elasticsearch node(s)?";
}
unless(
    defined($max_disk) and
    defined($min_disk_hostname) and
    defined($max_disk_hostname) and
    defined($min_disk_nodename) and
    defined($max_disk_nodename)
   ){
   quit "UNKNOWN", "failed to determine details for min/max disk/hostname/nodename. $nagios_plugins_support_msg";
}

# Changed to using direct % difference as it'll be simpler for users to understand
#
# guard against divide by zero
#my $divisor = $min_disk || 1;
#
#my $max_disk_imbalance = ( $max_disk - $min_disk ) / $divisor * 100;

my $max_disk_imbalance = $max_disk - $min_disk;

$max_disk_imbalance = sprintf("%.2f", $max_disk_imbalance);

plural $num_nodes;
$msg  = sprintf("Elasticsearch max disk %% difference = %.2f%%", $max_disk_imbalance);
check_thresholds($max_disk_imbalance);
$msg .= sprintf(" between %d node%s", $num_nodes, $plural);
plural $num_hosts;
$msg .= sprintf(" on %d host%s", $num_hosts, $plural);
if($verbose){
    $msg .= " (min disk = $min_disk% on host '$min_disk_hostname' name '$min_disk_nodename', max disk = $max_disk% on host '$max_disk_hostname' name '$max_disk_nodename')";
}
$msg .= " | max_disk_imbalance=$max_disk_imbalance%";
msg_perf_thresholds();
$msg .= " data_nodes=$num_nodes hosts=$num_hosts";

vlog2;
quit $status, $msg;
