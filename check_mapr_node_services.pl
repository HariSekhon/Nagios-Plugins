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

Tested on MapR 3.1.0 and 4.0.1";

$VERSION = "0.1";

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
);

get_options();

validate_mapr_options();
list_nodes();
$node = validate_host($node, "node");

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/service/list?node=$node", $user, $password;

my @data = get_field_array("data");

$msg = "services on node '$node' - ";
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
my $configured_services = 0;
foreach my $service (sort keys %node_services){
    # depends on service state mapping above in %service_states
    $configured_services++ if $node_services{$service} ne "not configured";
    if(not grep { $node_services{$service} eq $_ } ("running", "standby", "not configured")){
        critical;
        $node_services{$service} = uc $node_services{$service};
    }
    $msg .= $service . ":" . $node_services{$service} . ", ";
}
$msg =~ s/, $//;
unless($configured_services){
    quit "CRITICAL", "no services configured on node '$node', did you specify the correct node name? See --list-nodes";
}

vlog2;
quit $status, $msg;
