#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-11 20:11:15 +0100 (Fri, 11 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check Start/Stop state of a service/role in Cloudera Manager via CM Rest API

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 5.0.0, 5.7.0, 5.10.0, 5.12.0";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %cm_options,
    %cm_options_list,
);

delete $options{"I|hostId=s"};
delete $options{"A|activityId=s"};
delete $options{"N|nameservice=s"};

@usage_order = qw/host port user password tls ssl-CA-path tls-noverify cluster service roleId CM-mgmt list-activities list-clusters list-hosts list-nameservices list-roles list-services/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

vlog2;
set_timeout();

$status = "OK";

list_cm_components();

if(defined($cm_mgmt)){
    $url .= "$api/cm/service";
    if(defined($role)){
        $role = validate_cm_role();
        $url .= "/roles/$role";
    }
    if($cluster or $service or $hostid){
        usage "cannot mix --cluster/--service/--host and --CM-mgmt";
    }
} else {
    validate_cm_cluster_options();
}

cm_query();

my $state;
if(($cluster and $service) or defined($cm_mgmt)){
    if(defined($cm_mgmt)){
        $msg = "Cloudera Manager Mgmt service";
    } else {
        $msg = "cluster '$cluster' service '$service'";
    }
    if($role){
        check_cm_field("roleState");
        check_cm_field("type");
        if($verbose){
            $msg .= " role '$role'";
        } else {
            $msg .= " role '" . $json->{"type"} . "'";
        }
        $state = $json->{"roleState"};
    } else {
        check_cm_field("serviceState");
        $state = $json->{"serviceState"};
    }
} else {
    usage "must specify --cluster and --service and optionally --role";
}
$msg .= " state=$state";
if($state eq "STARTED"){
    # ok
} elsif(grep { $state eq $_ } qw/STARTING STOPPING/){
    warning;
} elsif(grep { $state eq $_ } qw/STOPPED/){
    critical;
} elsif(grep { $state eq $_ } qw/UNKNOWN HISTORY_NOT_AVAILABLE/){
    unknown;
} else {
    unknown;
    $msg .= " (state unrecognized. $nagios_plugins_support_msg_api)";
}

quit $status, $msg;
