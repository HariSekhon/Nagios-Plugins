#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-02 20:31:30 +0000 (Mon, 02 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop service states via Ambari REST API

Checks:

- all service states by default
or
- a given service's state

- optionally suppresses alerts in maintenance mode if using the switch --maintenance-ok
- reports but does not raise critical for components which do not have running states such as HCatalog, Kerberos, Pig, Slider, Sqoop, Tez. You can extend this list at the top of the code (in which case please submit a ticket for the rest of us to get the update too)

Tested on Ambari 1.4.4, 1.6.1, 1.7.0, 2.0.0, 2.1.0, 2.1.2, 2.2.1, 2.5.1 on Hortonworks HDP 2.0, 2.1, 2.2, 2.3, 2.4, 2.6";

$VERSION = "0.7";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

# Services without running components to exclude from raising critical (still output though) i
#
# I've moved this to the top for you users to easily add to as Ambari keeps adding components, if you just add it to this list below it won't raise critical
#
# Please raise a github ticket or even better submit a patch via a github pull request if you add to this list:
#
# https://github.com/harisekhon/nagios-plugins/issues
#
my @services_to_not_alert_on = qw(
                                    HCatalog
                                    Kerberos
                                    Pig
                                    Slider
                                    Sqoop
                                    Tez
                                 );

my $service_state       = 0;
my $all_service_states  = 0;
my $maintenance_ok      = 0;

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options_service,
    "maintenance-ok"            => [ \$maintenance_ok,      "Suppress service alerts in maintenance mode" ],
);
splice @usage_order, 10, 0, qw/maintenance-ok/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;
$service    = validate_ambari_service($service) if $service;
#$component  = validate_ambari_component($component) if $component;

validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

sub get_service_state($){
    my $json = shift() || code_error "no hash passed to get_service_state()";
    my $msg;
    my $service_name      = get_field2($json, "ServiceInfo.service_name");
    my $service_state     = get_field2($json, "ServiceInfo.state");
    my $maintenance_state = get_field2($json, "ServiceInfo.maintenance_state");
    $service_name = hadoop_service_name $service_name;
    if($maintenance_ok and $maintenance_state ne "OFF"){
        # suppress alerts if in maintenance mode and --maintenance-ok
        $maintenance_state = lc $maintenance_state;
    } elsif($service_state eq "STARTED"){
        # ok
        $service_state = lc $service_state;
    } elsif($service_state eq "INSTALLED"){
        if(grep { lc($service_name) eq lc($_) } @services_to_not_alert_on){
            #ok
            $service_state = lc $service_state;
        } else {
            $service_state = "STOPPED";
            critical;
        }
    } elsif($service_state eq "UNKNOWN"){
        unknown;
    } elsif(grep { $service_state eq $_ } qw/STARTING INIT UPGRADING MAINTENANCE INSTALLING/){
        warning;
    } elsif(grep { $service_state eq $_ } qw/INSTALL_FAILED STOPPING UNINSTALLING UNINSTALLED WIPING_OUT/){
        critical;
    } else {
        unknown;
    }
    $msg .= "$service_name=$service_state";
    if($verbose){
        $maintenance_state = lc $maintenance_state if $maintenance_state eq "OFF";
        $msg .= " (maintenance=$maintenance_state)";
    }
    return $msg;
}

$msg .= "Ambari service";
if($service){
    $json = curl_ambari "$url_prefix/clusters/$cluster/services/$service?fields=ServiceInfo/state,ServiceInfo/maintenance_state";
    $msg .= ": " . get_service_state($json);
} else {
    $msg .= "s: ";
    $json = curl_ambari "$url_prefix/clusters/$cluster/services?fields=ServiceInfo/state,ServiceInfo/maintenance_state";
    my @items = get_field_array("items");
    foreach(@items){
        $msg .= get_service_state($_) . ", ";
    }
    $msg =~ s/, $//;
}

vlog2;
quit $status, $msg;
