#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://doc.mapr.com/display/MapR/API+Reference

$DESCRIPTION = "Nagios Plugin to check MapR Control System information via the MCS REST API

Obsolete. Nearly all functionality has been stripped out. DO NOT USE except for CLDB listings

Used to support Service & Node health, MapR-FS Space Used %, Node count, Alarms, Failed Disks, Cluster Version & License, MapReduce statistics

Now see instead newer single purpose check_mapr_* plugins adjacent in the Advanced Nagios Plugins Collection as they offer cleaner code with better control and more features.

Tested on MapR 3.1 and 4.0 M3 & M7";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

#set_threshold_defaults(80, 90);

my $blacklist_users = 0;
my $disk            = 0;
my $license_apps    = 0;
my $list_cldbs      = 0;
my $list_vips       = 0;
my $listcldbzks     = 0;
my $listzookeepers  = 0;
my $node_metrics    = 0;
my $schedule        = 0;
my $ssl_port;
my $table_listrecent = 0;
my $volumes          = 0;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_node,
    %thresholdoptions,
    # XXX: not currently available via REST API as of 3.1
    # Update: MapR have said they probably won't implement this since they "don't use the metrics database to show these metrics anywhere"
    #"node-metrics"     => [ \$node_metrics,     "Node metrics" ],
    # XXX: check was I supposed to remove this?
    #"M|mapreduce-stats" => [ \$mapreduce_stats,  "MapReduce stats for graphing, raises critical if blacklisted > 0" ],
    "list-cldbs"       => [ \$list_cldbs,       "List CLDB nodes" ],
    #"L|license"        => [ \$license,          "Show license, requires --cluster" ],
    # Not that interesting to expose
    #"list-cldb-zks"            => [ \$listcldbzks,         "List CLDB & ZooKeeper nodes" ],
    #"list-schedule"            => [ \$schedule,            "List schedule" ],
    #"list-recent-tables"       => [ \$table_listrecent,    "List recent tables" ],
    #"list-vips"                => [ \$list_vips,           "List VIPs" ],
    #"list-volumes"             => [ \$volumes,             "List volumes" ],
    #"disk"                     => [ \$disk,                "Disk list" ],
    # TODO: MCS Bug: crashes Admin UI with cldb=$node and cluster
    #"list-zookeepers"          => [ \$listzookeepers,      "List ZooKeeper nodes (requires CLDB --node)" ],
    # TODO: MCS Bug: Not implemented as of MCS 3.1
    #"list-blacklisted-users"   => [ \$blacklist_users,     "List blacklisted users" ],
);

@usage_order = qw/host port user password cluster node node-alarms node-count node-health heartbeat mapreduce-stats list-clusters list-nodes list-cldbs list-vips ssl-CA-path ssl-noverify no-ssl warning critical/;

# TODO:
#
# Jobs running on cluster
#
# http://doc.mapr.com/display/MapR/job+table
#
# Tasks for a specific job
#
# http://doc.mapr.com/display/MapR/task+table

get_options();

validate_mapr_options();
$cluster = validate_cluster($cluster) if $cluster;

if($list_cldbs > 1){
    usage "can only specify one check at a time";
}

my $ip = validate_resolvable($host);
vlog2 "resolved $host to $ip";
my $url_prefix = "https://$ip:$port";
my $url = "";

# TODO: http://doc.mapr.com/display/MapR/node+metrics

# Not sure on the value of this
# } elsif($disk){
#     if($cluster){
#         $url .= "/disk/listall?cluster=$cluster";
#     } else {
#         $node = validate_host($node, "node");
#         $url .= "/disk/list?host=$node";
#     }
#     # TODO: system=0 MapR only, system=1 OS only disks, not specified == both
#     # XXX: http://doc.mapr.com/display/MapR/disk#disk-disk-fields
#     #
#} elsif($license_apps){
#    $cluster or usage "--license-apps requires --cluster";
#    $url = "/license/apps?cluster=$cluster";
if($list_cldbs){
    $url = "/node/listcldbs";
    $url = "?cluster=$cluster" if $cluster;
} elsif($list_vips){
    $url = "/virtualip/list";
# Don't need to list both at the same time
#} elsif($listcldbzks){
#    $url = "/node/listcldbzks";
#    $url = "?cluster=$cluster" if $cluster;
#
# MCS BUG: managed to crash the service 8443 so it's not even bound to port any more fiddling with these cluster and cldb combinations!
#} elsif($listzookeepers){
#    #$node or usage "--list-zookeepers requires CLDB --node";
#    $url = "/node/listzookeepers";
#    $url = "?cluster=$cluster" if $cluster;
#    # every time I send cldb=$node with cluster it crashes the admin UI
#    #$url = "&cldb=$node";
#} elsif($schedule){
#    $url = "/schedule/list";
#} elsif($table_listrecent){
#    $url = "/table/listrecent";
#} elsif($volumes){
#    $url = "/volume/list";
#
# TODO: MCS Bug - not be implemented as an endpoint and results in a 404 Not Found response
#} elsif($blacklist_users){
#    $url .= "/blacklist/listusers";
} else {
    usage "no check specified";
}
validate_ssl();
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr($url, $user, $password);

defined($json->{"status"}) or quit "UNKNOWN", "status field not found in output. $nagios_plugins_support_msg_api";
if($debug){
    use Data::Dumper;
    print Dumper($json);
    print "\n";
}
unless($json->{"status"} eq "OK"){
    my $err = "status=" . $json->{"status"} . " - ";
    if(defined($json->{"errors"})){
        foreach(@{$json->{"errors"}}){
            if(defined($_->{"desc"})){
                $err .= $_->{"desc"} . ".";
            }
        }
    }
    $err =~ s/\.$//;
    quit "CRITICAL", $err;
}
defined($json->{"total"}) or quit "UNKNOWN", "total field not defined. $nagios_plugins_support_msg";

defined($json->{"data"}) or quit "UNKNOWN", "data field not found in output. $nagios_plugins_support_msg";
isArray($json->{"data"}) or quit "UNKNOWN", "data field is not an array. $nagios_plugins_support_msg";

#if($mapreduce_stats){
#    foreach my $cluster (@{$json->{"data"}}){
#        defined($cluster->{"cluster"}{"name"}) or quit "UNKNOWN", "didn't find cluster name in output, format may have changed. $nagios_plugins_support_msg";
#        defined($cluster->{"utilization"}->{"memory"}->{"active"}) and defined($cluster->{"utilization"}->{"memory"}->{"total"}) or quit "UNKNOWN", "didn't find memory active/total in output, format may have changed. $nagios_plugins_support_msg";
#        $msg = "cluster: " . $cluster->{"cluster"}{"name"} . " ";
#        $msg .= sprintf("memory: %.2f%% active (%d/%d) ", $cluster->{"utilization"}->{"memory"}->{"active"} / $cluster->{"utilization"}->{"memory"}->{"total"} * 100, $cluster->{"utilization"}->{"memory"}->{"active"}, $cluster->{"utilization"}->{"memory"}->{"total"});
#        $msg .= "mapreduce: ";
#        my $msg2;
#        foreach my $stat (sort keys %{$cluster->{"mapreduce"}}){
#            quit "UNKNOWN", "non-integer result returned for $stat" if(!isInt($cluster->{"mapreduce"}->{$stat}));
#            $msg2 .= "$stat=" . $cluster->{"mapreduce"}->{$stat} . " ";
#        }
#        defined($cluster->{"mapreduce"}->{"blacklisted"}) or quit "UNKNOWN", "didn't find blacklisted in output, format may have changed. $nagios_plugins_support_msg";
#        if($cluster->{"mapreduce"}->{"blacklisted"}){
#            critical;
#        }
#        $msg .= $msg2;
#        $msg =~ s/blacklisted/BLACKLISTED/ if($cluster->{"mapreduce"}->{"blacklisted"});
#        $msg .= "| $msg2";
#    }
#} elsif($list_cldbs){
if($list_cldbs){
    # This count seems wrong, it states 1 when listing 2 different nodes
    #plural $json->{"total"};
    #$msg = $json->{"total"} . " CLDB node$plural";
    $msg = "CLDB nodes";
    $msg .= " in cluster '$cluster'" if $cluster;
    my @cldb_nodes;
    foreach(@{$json->{"data"}}){
        push(@cldb_nodes, $_->{"CLDBs"});
    }
    $msg .= ": " . join(", ", sort @cldb_nodes);
} elsif($list_vips){
    $msg = sprintf("%d VIPs", $json->{"total"});
} else {
    code_error "caught late - no check specified";
}

quit $status, $msg;
