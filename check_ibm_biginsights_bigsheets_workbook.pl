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

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.analyze.doc/doc/bigsheets_restapi.html

$DESCRIPTION = "Nagios Plugin to check the last run status of an IBM BigInsights BigSheets Workbook via BigInsights Console REST API

Thanks to Abhijit V Lele @ IBM for providing discussion feedback and additional BigInsights API resources that lead to the idea for this check

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use URI::Escape;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $workbook;
my $list_workbooks = 0;

%options = (
    %biginsights_options,
    "W|workbook=s"   =>  [ \$workbook,       "BigSheets Workbook name as displayed in BigInsights Console under BigSheets tab" ],
    "list-workbooks" =>  [ \$list_workbooks, "List BigSheets workbooks" ],
);
splice @usage_order, 4, 0, qw/workbook list-workbooks/;

get_options();

$host     = validate_host($host);
$port     = validate_port($port);
$user     = validate_user($user);
$password = validate_password($password);
unless($list_workbooks){
    defined($workbook) or usage "workbook not defined";
#$workbook =~ /^([\w\s\%-]+)$/ or usage "invalid workbook name given, may only contain: alphanumeric, dashes, spaces";
#$workbook = $1;
# switched to uri escape but not doing it here, as we want to preserve the name for the final output
#$workbook = uri_escape($workbook);
    vlog_option "workbook", $workbook;
}
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

if($list_workbooks){
    curl_bigsheets "/workbooks", $user, $password;
    isArray(get_field("workbooks")) or quit "UNKNOWN", "'workbooks' field returned by BigInsights Console is not an array! $nagios_plugins_support_msg_api";
    print "BigSheets Workbooks:\n\n";
    foreach (@{$json->{"workbooks"}}){
        printf "%s\n", get_field2($_, "name");
    }
    exit $ERRORS{"UNKNOWN"};
}

$json = curl_bigsheets "/workbooks/" . uri_escape($workbook) . "?type=status", $user, $password;

my $jobStatus       = get_field("status");
my $jobstatusString = get_field("jobstatusString");
if($jobStatus eq "OK"){
} elsif($jobStatus eq "WARNING"){
    warning;
} elsif($jobStatus eq "UNKNOWN"){
    unknown;
} else {         # eq "ERROR"
    critical;
}

$msg = "workbook '$workbook' status: $status - $jobstatusString";

quit $status, $msg;
