#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-05-15 23:13:05 +0100 (Thu, 15 May 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.dev.doc/doc/rest_access_app_admin.html

$DESCRIPTION = "Nagios Plugin to check the deployed status of an IBM BigInsights Application via BigInsights Console REST API

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use Data::Dumper;
use URI::Escape;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $app;
my $list_apps;

%options = (
    %biginsights_options,
    "A|application=s"   =>  [ \$app,        "Application name as displayed in BigInsights Console under Applications tab" ],
    "list-applications" =>  [ \$list_apps,  "List applications currently deployed in BigInsights Console" ],
);
splice @usage_order, 4, 0, qw/application list-applications/;

get_options();

$host     = validate_host($host);
$port     = validate_port($port);
$user     = validate_user($user);
$password = validate_password($password);
unless($list_apps){
    defined($app) or usage "application not defined";
    vlog_option "application", $app;
}
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

sub check_array($$){
    my $name = shift;
    my $ref  = shift;
    isArray($ref) or quit "UNKNOWN", "'$name' field is not an array as expected! $nagios_plugins_support_msg_api";
}

sub check_hash($$){
    my $name = shift;
    my $ref  = shift;
    isHash($ref) or quit "UNKNOWN", "'$name' field is not a hash as expected! $nagios_plugins_support_msg_api";
}

sub validate_app_name($){
    my $app_name = shift;
    defined($app_name) or quit "UNKNOWN", "app name not defined. $nagios_plugins_support_msg";
    $app_name =~ /^([A-Za-z0-9][\w\s-]+[A-Za-z0-9])$/ or quit "UNKNOWN", "invalid app name returned: '$app_name'. $nagios_plugins_support_msg";
    $app_name = $1;
    return $app_name;
}

sub validate_app_id($){
    my $app_id = shift;
    defined($app_id) or quit "UNKNOWN", "app id not defined. $nagios_plugins_support_msg";
    $app_id =~ /^([A-Za-z0-9][\w\s-]+[A-Za-z0-9])$/ or quit "UNKNOWN", "invalid app id returned: '$app_id'. $nagios_plugins_support_msg";
    $app_id = $1;
    return $app_id;
}

my %apps;

curl_biginsights "/catalog/applications?format=json", $user, $password;
my $metadata = get_field("metaData");
check_hash("metaData", $metadata);
my $column = get_field2($metadata, "column");
check_array("column", $column);
scalar @{$column} > 7 or quit "UNKNOWN", "'column' metadata array is too short! $nagios_plugins_support_msg_api";
my $name = $$column[1];
check_hash("col[1] name", $name);
get_field2($name, "name") eq "NAME" or quit "UNKNOWN", "'NAME' metadata field not found where expected! $nagios_plugins_support_msg_api";
my $app_status = $$column[7];
check_hash("col[7] name", $app_status);
get_field2($app_status, "name") eq "STATUS" or quit "UNKNOWN", "'STATUS' metadata field not found where expected! $nagios_plugins_support_msg_api";
my $data = get_field("data");
check_array("data", $data);
my $row;
foreach (@{$data}){
    $row = get_field2($_, "row");
    check_array("row", $row);
    foreach(@{$row}){
        check_hash("row element", $_);
        $column = get_field2($_, "column");
        check_array("row column", $column);
        scalar @{$column} > 7 or quit "UNKNOWN", "row column is too short! $nagios_plugins_support_msg_api";
        $apps{validate_app_name($$column[1])}{"id"}     = validate_app_id($$column[0]);
        $apps{validate_app_name($$column[1])}{"status"} = $$column[7];
    }
}

if($list_apps){
    print "BigInsights Applications:\n\n";
    my $format_string = "%-30s %-20s %-20s\n";
    printf "$format_string\n", "Application Name", "Status", "Application ID";
    foreach(sort keys %apps){
        printf $format_string, $_, $apps{$_}{"status"}, $apps{$_}{"id"};
    }
    exit $ERRORS{"UNKNOWN"};
}

grep { $app eq $_ } %apps or quit "CRITICAL", "no application with name '$app' in BigInsights Console! Did you specify the correct --application name? Use --list-applications to see all applications and their deployment status";

# not getting any more valuable information from that point, would have to go to Oozie to see last execution runs outcomes
#curl_biginsights "/catalog/applications/" . uri_escape($apps{$app}{"id"}) . "/runs?format=json", $user, $password;

$app_status = $apps{$app}{"status"};

critical if $app_status ne "DEPLOYED";

$msg = "application '$app' status: $app_status";

quit $status, $msg;
