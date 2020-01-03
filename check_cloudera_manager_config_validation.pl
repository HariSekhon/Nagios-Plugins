#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-13 20:58:38 +0100 (Sun, 13 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check Cloudera Manager config validation for services/roles via CM Rest API

Use verbose mode to print explanations for any non-OK configs if available

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 5.0.0, 5.7.0, 5.10.0, 5.12.0";

our $VERSION = "0.2.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $stale    = 0;
my $validate = 0;

my $cm       = 0;

%options = (
    %hostoptions,
    %useroptions,
    %cm_options,
    %cm_options_list,
    "CM"    =>  [ \$cm,     "Cloudera Manager config" ],
);

delete $options{"I|hostId=s"};
delete $options{"activityId=s"};
delete $options{"N|nameservice=s"};

@usage_order = qw/host port user password tls ssl-CA-path tls-noverify cluster service hostId activityId nameservice roleId CM CM-mgmt list-activities list-clusters list-hosts list-nameservices list-roles list-services list-users/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

list_cm_components();

if($cm){
    if($cluster or $service or $hostid or $cm_mgmt){
        usage "cannot mix --cluster/--service/--host/--CM-mgmt and --CM";
    }
    $url .= "$api/cm";
} elsif($cm_mgmt){
    if($cluster or $service or $hostid or $cm){
        usage "cannot mix --cluster/--service/--host/--CM and --CM-mgmt";
    }
    $url .= "$api/cm/service";
    if(defined($role)){
        $url .= "/roles/$role";
    }
} else {
    validate_cm_cluster_options();
}

$url .= "/config?view=full";

cm_query();

my $shortrole;

if($cm){
    $msg = "Cloudera Manager";
} elsif(($cluster and $service) or $cm_mgmt){
    if($cm_mgmt){
        $msg = "Cloudera Manager Mgmt service";
    } else {
        $msg = "cluster '$cluster' service '$service'";
    }
    if($role){
        $role =~ /^[^-]+-([^-]+)-/ or quit "UNKNOWN", "unknown role not in expected format. $nagios_plugins_support_msg";
        $shortrole = $1;
        if($verbose){
            $msg .= " role '$role'";
        } else {
            $msg .= " role '$shortrole'";
        }
    }
} elsif($hostid){
    $msg = "host '$hostid'";
} else {
    usage "must specify one of: --hostId, --cluster/--service or --CM-mgmt and optionally --role, --CM";
}
check_cm_field("items");
my $validationState;
my $validationMessage;
my $ok_count = 0;
my %warning_configs;
my %error_configs;
my %unknown_configs;

sub parse_config_states($@){
    my $role  = shift;
    my @items = shift;
    foreach my $item (@{$json->{"items"}}){
        foreach(qw/name validationState/){
            $item->{$_} or quit "UNKNOWN", "'$_' field not found for configuration item. $nagios_plugins_support_msg_api";
        }
        $validationState   = $item->{"validationState"};
        $validationMessage = ( defined($json->{"validationMessage"}) ? $json->{"validationMessage"} : "no validationMessage" );
        if($validationState eq "OK"){
            $ok_count++;
        } elsif($validationState eq "WARNING"){
            warning;
            $warning_configs{$role}{$item->{"name"}} = $validationMessage;
        } elsif($validationState eq "ERROR"){
            critical;
            $error_configs{$role}{$item->{"name"}}   = $validationMessage;
        } else {
            unknown;
            $unknown_configs{$role}{$item->{"name"}} = $validationMessage;
        }
    }
}
if(defined($json->{"roleTypeConfigs"})){
    isArray($json->{"roleTypeConfigs"}) or quit "UNKNOWN", "roleTypeConfigs is not an array! $nagios_plugins_support_msg_api";
    foreach(@{$json->{"roleTypeConfigs"}}){
        defined($_->{"roleType"}) or quit "UNKNOWN", "roleType not defined. $nagios_plugins_support_msg_api";
        my $role = $_->{"roleType"};
        parse_config_states($role, @{$_->{"items"}});
    }
}
parse_config_states("", @{$json->{"items"}});

my $warning_count = 0;
foreach(keys %warning_configs){
    $warning_count += scalar keys %{$warning_configs{$_}};
}

my $error_count = 0;
foreach(keys %error_configs){
    $error_count += scalar keys %{$error_configs{$_}};
}

my $unknown_count = 0;
foreach(keys %unknown_configs){
    $unknown_count += scalar keys %{$unknown_configs{$_}};
}

quit "UNKNOWN", "failed to validate any configs. $nagios_plugins_support_msg_api" unless ($ok_count + $warning_count + $error_count + $unknown_count);

$msg .= " config items: $ok_count OK";
if($warning_count){
    $msg .= ", $warning_count WARNING";
    if($verbose){
        $msg .= " (";
        foreach my $role (sort keys %warning_configs){
            $msg .= "[$role: " if $role;
            foreach(sort keys %{$warning_configs{$role}}){
                $msg .= "$_='$warning_configs{$role}{$_}', ";
            }
            $msg =~ s/, $/], / if $role;
        }
        $msg =~ s/, $/)/;
    }
}
if($error_count){
    $msg .= ", $error_count ERROR";
    if($verbose){
        $msg .= " (";
        foreach my $role (sort keys %error_configs){
            $msg .= "[$role: " if $role;
            foreach(sort keys %{$error_configs{$role}}){
                $msg .= "$_='$error_configs{$role}{$_}', ";
            }
            $msg =~ s/, $/], / if $role;
        }
        $msg =~ s/, $/)/;
    }
}
if($unknown_count){
    $msg .= ", $unknown_count UNKKNOWN";
    if($verbose){
        $msg .= " (";
        foreach my $role (sort keys %unknown_configs){
            $msg .= "[$role: " if $role;
            foreach(sort keys %{$unknown_configs{$role}}){
                $msg .= "$_='$unknown_configs{$role}{$_}', ";
            }
            $msg =~ s/, $/], / if $role;
        }
        $msg =~ s/, $/)/;
    }
}

quit $status, $msg;
