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

$DESCRIPTION = "Nagios Plugin to check Cloudera Manager service/role config staleness (restart required) via CM Rest API

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 5.0.0, 5.7.0";

our $VERSION = "0.1";

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

$api = "/api/v1";

%options = (
    %hostoptions,
    %useroptions,
    %cm_options,
    %cm_options_list,
);

delete $options{"I|hostId=s"};
delete $options{"activityId=s"};
delete $options{"N|nameservice=s"};

@usage_order = qw/host port user password tls ssl-CA-path tls-noverify cluster service hostId activityId nameservice roleId CM-mgmt list-activities list-clusters list-hosts list-nameservices list-roles list-services list-users/;

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

if($cm_mgmt){
    if($cluster or $service){
        usage "cannot mix --cluster/--service/--host and --CM-mgmt";
    }
    $url .= "$api/cm/service";
    if(defined($role)){
        $url .= "/roles/$role";
    }
} else {
    validate_cm_cluster_options();
}

cm_query();

check_cm_field("configStale");
my $configStale = $json->{"configStale"};
# 'configStale' => bless( do{\(my $o = 0)}, 'JSON::PP::Boolean' ),
#critical unless (grep { $configStale =~ /^$_$/i } qw/0 false/);
warning if $configStale;

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
} else {
    usage "must specify --cluster/--service or --CM-mgmt and optionally --role";
}
$msg .= " configStale=" . ($configStale ? "true" : "false");

quit $status, $msg;
