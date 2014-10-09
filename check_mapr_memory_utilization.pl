#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check a MapR cluster's memory utilization % via the MapR Control System REST API

Checks optional warning/critical thresholds against memory utilization %.

Tested on MapR 3.1.0 and 4.0.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %thresholdoptions,
);

get_options();

validate_mapr_options();
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100});

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/dashboard/info", $user, $password;

my @data = get_field_array("data");

my $name;
my $msg2;
foreach my $cluster (@data){
    $name = get_field2($cluster, "cluster.name");
    $msg .= "cluster: '$name' ";
    my $memory_active    = get_field2($cluster, "utilization.memory.active");
    my $memory_total     = get_field2($cluster, "utilization.memory.total");
    my $memory_active_pc = sprintf("%.2f", $memory_active / $memory_total * 100);
    $msg .= sprintf("memory: %.2f%% active", $memory_active_pc);
    check_thresholds($memory_active_pc);
    $msg .= sprintf(" [%d/%dMB]', ", $memory_active, $memory_total);
    $msg2 .= " 'cluster $name active memory %'=${memory_active_pc}%" . msg_perf_thresholds(1) . " 'cluster $name active memory'=${memory_active}MB 'cluster $name total_memory'=${memory_total}MB";
}
$msg =~ s/, $//;
$msg .= " |$msg2";

vlog2;
quit $status, $msg;
