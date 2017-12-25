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

$DESCRIPTION = "Nagios Plugin to check all services on a given MapR Hadoop node via the MapR Control System REST API

Can optionally specify just a single service to check on the given node.

Currently the MCS API doesn't support service information at the cluster level, which is why you have to specify a node to check services on.

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

# http://doc.mapr.com/display/MapR/service+list
#
#    0 - NOT_CONFIGURED: the package for the service is not installed and/or the service is not configured (configure.sh has not run)
#    2 - RUNNING: the service is installed, has been started by the warden, and is currently executing
#    3 - STOPPED: the service is installed and configure.sh has run, but the service is currently not executing
#    5 - STAND_BY: the service is installed and is in standby mode, waiting to take over in case of failure of another instance (mainly used for JobTracker warm standby)
my %service_states = (
    0 => "not configured",
    2 => "running",
    3 => "stopped",
    # state 4 is Failed, currently undocumented as of MapR 3.1, MapR guys said they will document this
    4 => "failed",
    5 => "standby",
);

%options = (
    %mapr_options,
    %mapr_option_node,
    %mapr_option_service,
);

get_options();

validate_mapr_options();

vlog2;
set_timeout();

list_nodes();
$node = validate_host($node, "node");
list_services();
$service = validate_service($service) if $service;

$status = "OK";

$json = curl_mapr "/service/list?node=$node", $user, $password;

my @data = get_field_array("data");

if($service){
    $msg = "node '$node' service '$service' = ";
} else {
    $msg = "services on node '$node' - ";
}
my %node_services;
foreach (@data){
    my $displayname = get_field2($_, "displayname");
    my $state       = get_field2($_, "state");
    if(grep { $state eq $_ } keys %service_states){
        $node_services{$displayname} = $service_states{$state};
    } else {
        $node_services{$displayname} = "unknown";
    }
}

my $found_service;
my $configured_services = 0;
foreach my $service2 (sort keys %node_services){
    $configured_services++ if $node_services{$service2} ne "not configured";
    if(defined($service)){
        next unless $service eq $service2;
        $found_service++;
    }
    # depends on service state mapping above in %service_states
    if(not grep { $node_services{$service2} eq $_ } ("running", "standby", "not configured")){
        critical;
        $node_services{$service2} = uc $node_services{$service2};
    }
    if($service){
        $msg .= $node_services{$service2};
    } else {
        $msg .= $service2 . ":" . $node_services{$service2} . ", ";
    }
}
$msg =~ s/, $//;
unless($configured_services){
    quit "CRITICAL", "no services configured on node '$node', did you specify the correct node name? See --list-nodes";
}
if($service and not $found_service){
    quit "CRITICAL", "service '$service' was not found on node '$node', did you specify the correct service? See --list-services";
}

vlog2;
quit $status, $msg;
