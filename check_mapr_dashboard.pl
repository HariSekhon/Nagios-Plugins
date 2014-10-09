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

$DESCRIPTION = "Nagios Plugin to check MapR's dashboard of Hadoop cluster services, memory utilization % and mounted/unmounted volumes via the MapR Control System REST API

Raises CRTIICAL if any services have failed.

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

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/dashboard/info", $user, $password;

my @data = get_field_array("data");

my $name;
my $msg2;
my $msg3;
my %services;
my $volumes_mounted;
my $volumes_unmounted;
foreach my $cluster (@data){
    $name = get_field2($cluster, "cluster.name");
    $msg .= "cluster: '$name' ";
    my $memory_active    = get_field2($cluster, "utilization.memory.active");
    my $memory_total     = get_field2($cluster, "utilization.memory.total");
    my $memory_active_pc = $memory_active / $memory_total * 100;
    $msg .= sprintf("memory: %.2f%% active (%d/%d) ", $memory_active_pc, $memory_active, $memory_total);
    $msg3 .= " 'cluster $name active memory %'=$memory_active_pc% 'cluster $name active memory'=$memory_active 'cluster $name total_memory'=$memory_total";
    $msg .= "services: ";
    %services = get_field2_hash($cluster, "services");
    foreach my $service (sort keys %services){
        $msg2 = "";
        foreach(qw/active standby stopped failed/){
            if(defined($cluster->{"services"}->{$service}->{$_}) and $cluster->{"services"}->{$service}->{$_}){
                $msg2 .= ($_ eq "failed" ? "FAILED" : $_ ) . "=" . get_field2($cluster, "services.$service.$_") . " ";
                critical if($_ eq "failed");
            }
        }
        $msg2 =~ s/ $//;
        $msg2 = "$service $msg2" if $msg2;
        $msg .= "$msg2, ";
    }
    $msg =~ s/, $//;
    $volumes_mounted   = get_field2($cluster, "volumes.mounted.total");
    $volumes_unmounted = get_field2($cluster, "volumes.unmounted.total");
    $msg .= sprintf(", volumes: mounted=%d unmounted=%d, ", $volumes_mounted, $volumes_unmounted);
    $msg3 .= " 'cluster $name volumes mounted'=$volumes_mounted 'cluster $name volumes unmounted'=$volumes_unmounted";
}
$msg =~ s/, $//;
$msg .= " |$msg3";

vlog2;
quit $status, $msg;
