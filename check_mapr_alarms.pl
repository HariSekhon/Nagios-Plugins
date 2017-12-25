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

$DESCRIPTION = "Nagios Plugin to check for MapR alarms via the MapR Control System REST API

Can optionally specifying cluster and/or an entity to restrict the alarm search (\"CLUSTER\" level (eg. license expiry), node name, volume, user or group). Automatically excludes cleared alarms.

Since the API doesn't respect entity search, filtering is done inside this plugin, which means that specifying the wrong entity name will result in 0 alarms being detected.

Verbose mode prints the alarm descriptions in brackets.

Perfdata is always output for the number of alarms.

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

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

set_threshold_defaults(0, 1);

my $entity = "";
my $exclude_core;
my $exclude_license;
my $exclude_unknown_service_state;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    "E|entity=s"         => [ \$entity, "Entity to check (cluster, node, volume, user or group to check alarms for)" ],
    "exclude-core-files" => [ \$exclude_core,    "Exclude alarms for core files" ],
    "exclude-license"    => [ \$exclude_license, "Exclude alarms for license expiry (only use this if checking this separately with check_mapr_license.pl)" ],
    "exclude-unknown-service-state" => [ \$exclude_unknown_service_state, "Exclude alarms for unknown service states" ],
    %thresholdoptions,
);
splice @usage_order, 8, 0, qw/entity exclude-core-files exclude-license exclude-unknown-service-state/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster $cluster if $cluster;

vlog2;
set_timeout();

$status = "OK";

my $url = "/alarm/list";
if($cluster or $entity){
    $url .= "?";
    $url .= "cluster=$cluster" if $cluster;
    $url .= "&" if $cluster and $entity;
    # This doesn't actually restrict to this entities, another BUG in MCS => filtering later on as a result
    $url .= "entity=$entity" if $entity;
}
$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %entity_alarms;

my $entity_name = $entity;
my $alarm_name;
my $alarm_state;
my $alarm_time;
my $description;
foreach my $item (@data){
    $entity = get_field2($item, "entity");
    next if($entity_name and $entity ne $entity_name);
    next unless get_field2($item, "alarm state"); # ignore alarm state 0 (cleared alarms)
    $alarm_name  = get_field2($item, "alarm name");
    next if($exclude_core    and $alarm_name eq "NODE_ALARM_CORE_PRESENT");
    next if($exclude_license and $alarm_name eq "CLUSTER_ALARM_LICENSE_NEAR_EXPIRATION");
    $alarm_time  = get_field2($item, "alarm statechange time");
    $description  = get_field2($item, "description");
    next if($exclude_unknown_service_state and $description =~ /Can not determine if service: .+ is running/i);
    if($entity_alarms{$entity}{$alarm_name}){
        if($alarm_time > $entity_alarms{$entity}{$alarm_name}{"alarm_time"}){
            $entity_alarms{$entity}{$alarm_name}{"alarm_time"}  = $alarm_time;
            $entity_alarms{$entity}{$alarm_name}{"description"} = $description;
        }
    } else {
        $entity_alarms{$entity}{$alarm_name}{"alarm_time"}  = $alarm_time;
        $entity_alarms{$entity}{$alarm_name}{"description"} = $description;
    }
}

my $now = time;
my $alarm_count = 0;
if(%entity_alarms){
    $msg = "alarms for ";
    foreach $entity (sort keys %entity_alarms){
        $msg .= "'$entity': ";
        foreach $alarm_name (sort keys %{$entity_alarms{$entity}}){
            $alarm_count++;
            if($entity_alarms{$entity}{$alarm_name}{"description"} =~ /not determine|node has core file/i){
                warning;
            } else {
                critical;
            }
            $msg .= "$alarm_name";
            if($verbose){
                $msg .= " ($entity_alarms{$entity}{$alarm_name}{description})";
            }
            $msg .= ", ";
        }
    }
    $msg =~ s/, $//;
    $msg .= " | alarm_count=$alarm_count";
} else {
    $msg = "no alarms found";
    $msg .= " for entity '$entity_name'" if $entity_name;
    $msg .= " | alarm_count=0";
}

vlog2;
quit $status, $msg;
