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

$DESCRIPTION = "Nagios Plugin to check MapR Hadoop services via the MapR Control System REST API

Shows running out of total instances for each service, raises CRITICAL if any service has failed or stopped instances.

Can optionally specify a cluster and/or just a single service to check.

Specifying the cluster name shortens the perfdata labels to not have to include the cluster name to differentiate potentially multiple clusters

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.2";

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
    %mapr_option_service,
);

get_options();

validate_mapr_options();
$cluster = validate_cluster($cluster) if $cluster;
$service = validate_service($service) if $service;

vlog2;
set_timeout();

list_clusters();
list_services();

$status = "OK";

my $url = "/dashboard/info";
$url .= "?cluster=$cluster" if $cluster;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my $msg2 = "";

my $name;
my %services;

my $active;
my $failed;
my $standby;
my $stopped;
my $total;

my $found_service;

foreach (@data){
    $name = get_field2($_, "cluster.name");
    $msg .= "cluster: '$name' service instances running: ";
    if(not defined($_->{"services"}) and $cluster){
        quit "UNKNOWN", "services field not found. Try unsetting \$MAPR_CLUSTER and not using --cluster / -C switch as sometimes services don't show up for the specific cluster";
    }
    %services = get_field2_hash($_, "services");
    foreach my $service2 (sort keys %services){
        if($service){
            next unless $service eq $service2;
        }
        $found_service++;
        $msg    .= "$service2 ";
        $active  = get_field2_int($services{$service2}, "active");
        $failed  = get_field2_int($services{$service2}, "failed");
        $standby = get_field2_int($services{$service2}, "standby", "noquit");
        $stopped = get_field2_int($services{$service2}, "stopped");
        $total   = get_field2_int($services{$service2}, "total");
        $msg .= ($total - $failed - $stopped) . "/$total";
        critical if $failed or $stopped;
        if($failed or $stopped or $verbose){
            $msg .= " [";
            #$msg .= "active=$active, ";
            $msg .= "failed=$failed, " if $failed or $verbose;
            $msg .= "standby=$standby, " if defined($standby);
            $msg .= "stopped=$stopped" if $stopped or $verbose;
            #$msg .= ", total=$total";
            $msg =~ s/, $//;
            $msg .= "]";
        }
        $msg .= ", ";
        $msg2 .= sprintf(" '%s%s active'=%d", ($cluster ? "" : "cluster $name service "), $service2, $active);
        $msg2 .= sprintf(" '%s%s failed'=%d", ($cluster ? "" : "cluster $name service "), $service2, $failed);
        $msg2 .= sprintf(" '%s%s standby'=%d", ($cluster ? "" : "cluster $name service "), $service2, $standby) if defined($standby);
        $msg2 .= sprintf(" '%s%s stopped'=%d", ($cluster ? "" : "cluster $name service "), $service2, $stopped);
    }
}
if($service and not $found_service){
    quit "UNKNOWN", "service '$service' not found, did you specify the correct service name? See --list-services";
} elsif(not $found_service){
    quit "UNKNOWN", "no services found! $nagios_plugins_support_msg_api";
}
$msg =~ s/, $//;
$msg .= " |$msg2";

vlog2;
quit $status, $msg;
