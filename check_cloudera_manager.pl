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

$DESCRIPTION = "Nagios Plugin to check Cloudera Manager API ping via CM Rest API

Alternatively lists users and in verbose mode also roles for each user in Cloudera Manager

Use API ping as a base dependency check for the real checks in adjacent check_cloudera_manager_*.pl plugins.

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 4.8.2, 5.0.0, 5.7.0, 5.10.0, 5.12.0";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api_ping   = 0;
my $list_users = 0;

%options = (
    %hostoptions,
    %useroptions,
    %thresholdoptions,
    #%cm_options,
    %cm_options_tls,
    %cm_option_cluster,
    %cm_options_list_basic,
    "api-ping"          =>  [ \$api_ping,           "Test Cloudera Manager API (use this as a base dependency check for all CM based checks)" ],
    "list-users"        =>  [ \$list_users,         "List users in Cloudera Manager (verbose mode shows each user's roles in format user[role] eg admin[ROLE_ADMIN])" ],
);

@usage_order = qw/host port user password api-ping list-users tls ssl-CA-path tls-noverify cluster service hostId activityId nameservice roleId CM-mgmt list-activities list-clusters list-hosts list-nameservices list-roles list-services list-users warning critical/;

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
# XXX: could extend this to do user whitelisting here
if($list_users){
    $url = "$api/users";
    cm_query();
    check_cm_field("items");
    $msg = "users: ";
    foreach(@{$json->{"items"}}){
        #foreach my $field (qw/name roles/){
        foreach my $field (qw/name/){
            defined($_->{$field}) or quit "CRITICAL", "$field field not found in user items returned from '$url_prefix'. You may not have permissions to query this or $nagios_plugins_support_msg_api";
        }
        $msg .= $_->{"name"};
        if($verbose and isArray($_->{"roles"})){
            $msg .= "[";
            #isArray($_->{"roles"}) or quit "UNKNOWN", "roles returned for user not an array. You may not have permissions to query this or $nagios_plugins_support_msg_api";
            $msg .= join(",", @{$_->{"roles"}});
            $msg .= "]";
        }
        $msg .= ", ";
    }
    $msg =~ s/, $//;
    quit $status, $msg;
#} elsif($api_ping){
} else {
    my $api_message = random_alnum(20);
    vlog2 "random string to push through CM API: $api_message";
    $url = "$api/tools/echo?message=$api_message";
    cm_query();
    check_cm_field("message");
    if($json->{"message"} eq $api_message){
        $msg = "API ping successful to Cloudera Manager";
    } else {
        critical;
        $msg = "API ping failed to return the correct message from Cloudera Manager (expected: '$api_message', got: '" . $json->{"message"} . "')";
    }
    quit $status, $msg;
}

#validate_cm_cluster_options();

#cm_query();

quit $status, $msg;
