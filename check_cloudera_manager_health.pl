#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-14 11:58:18 +0000 (Thu, 14 Nov 2013)
#  redo  2014-04-13 19:45:41 +0100 (Sun, 13 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check service/role/host health in Cloudera Manager via CM Rest API

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 5.0.0";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $cm_mgmt = 0;

%options = (
    %hostoptions,
    %useroptions,
    %cm_options,
    %cm_options_list,
    "CM-mgmt"       => [ \$cm_mgmt,     "Cloudera Manager Management service health" ],
);

delete $options{"activityId=s"};
delete $options{"N|nameservice=s"};

@usage_order = qw/host port user password tls ssl-CA-path tls-noverify CM-mgmt cluster service hostId activityId nameservice roleId list-activities list-clusters list-hosts list-nameservices list-roles list-services/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

vlog2;
set_timeout();

$status = "OK";

list_cm_components();

if($cm_mgmt){
    $url .= "$api/cm/service";
    if($cluster or $service or $role or $hostid){
        usage "cannot mix --cluster/--service/--role/--host and --CM-mgmt";
    }
} else {
    validate_cm_cluster_options();
}

cm_query();

check_cm_field("healthSummary");
my $health = $json->{"healthSummary"};

if(($cluster and $service) or $cm_mgmt){
    if($cm_mgmt){
        $msg = "Cloudera Manager Mgmt service";
    } else {
        $msg = "cluster '$cluster' service '$service'";
    }
    if($role){
        check_cm_field("type");
        if($verbose){
            $msg .= " role '$role'";
        } else {
            $msg .= " role '" . $json->{"type"} . "'"; 
        }
    }
} elsif($hostid){
    $msg = "host '$hostid'";
} else {
    usage "must specify --hostId, or --cluster/--service and optionally --role";
}
$msg .= " health=$health";
if($health eq "GOOD"){
    # ok
} elsif(grep { $health eq $_ } qw/CONCERNING/){
    warning;
} elsif(grep { $health eq $_ } qw/BAD DISABLED/){ # DISABLED implies STOPPED state
    critical;
} elsif(grep { $health eq $_ } qw/UNKNOWN NOT_AVAILABLE HISTORY_NOT_AVAILABLE/){
    unknown;
} else {
    unknown;
    $msg .= " (health unrecognized. $nagios_plugins_support_msg_api)";
}

quit $status, $msg;
