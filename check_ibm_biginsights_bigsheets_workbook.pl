#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-05-15 23:13:05 +0100 (Thu, 15 May 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the last run status of an IBM BigInsights BigSheets Workbook via BigInsights Console REST API

Thanks to Abhijit V Lele @ IBM for providing discussion feedback and additional BigInsights API resources that lead to the idea for this check

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON;
use LWP::Simple '$ua';
use URI::Escape;

set_port_default(8080);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api = "data/controller";

our $protocol = "http";

my $workbook;

%options = (
    %hostoptions,
    %useroptions,
    "W|workbook=s"  =>  [ \$workbook,   "BigSheets Workbook name as displayed in BigInsights Console under BigSheets tab" ],
    %tlsoptions,
);
@usage_order = qw/host port user password workbook tls ssl-CA-path tls-noverify/;

get_options();

$host     = validate_host($host);
$port     = validate_port($port);
$user     = validate_user($user);
$password = validate_password($password);
defined($workbook) or usage "workbook not defined";
#$workbook =~ /^([\w\s\%-]+)$/ or usage "invalid workbook name given, may only contain: alphanumeric, dashes, spaces";
#$workbook = $1;
# switched to uri escape but not doing it here, as we want to preserve the name for the final output
#$workbook = uri_escape($workbook);
vlog_options "workbook", $workbook;

tls_options();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

my $url = "$url_prefix/bigsheets/api/workbooks/" . uri_escape($workbook) . "?type=status";

validate_resolvable($host);
vlog2 "querying IBM BigInsights Console";
vlog3 "HTTP GET $url (basic authentication)";
$ua->show_progress(1) if $debug;
my $req = HTTP::Request->new('GET', $url);
$req->authorization_basic($user, $password) if (defined($user) and defined($password));
my $response = $ua->request($req);
my $content  = $response->content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http status code:     " . $response->code;
vlog2 "http status message:  " . $response->message . "\n";
my $json;
my $additional_information = "";
if($json = isJson($content)){
    if(defined($json->{"status"})){
        $additional_information .= ". Status: " . $json->{"status"};
    }
    if(defined($json->{"errorMsg"})){
        $additional_information .= ". Reason: " . $json->{"errorMsg"};
    }
}
unless($response->code eq "200" or $response->code eq "201"){
    quit "CRITICAL", $response->code . " " . $response->message . $additional_information;
}
if(defined($json->{"errorMsg"})){
    if($json->{"errorMsg"} eq "Could not get Job status: null"){
        quit "UNKNOWN", "worksheet job run status: null (workbook not been run yet?)";
    }
    $additional_information =~ s/^\.\s+//;
    quit "CRITICAL", $additional_information;
}
unless($content){
    quit "CRITICAL", "blank content returned from '$url'";
}

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix', did you try to connect to the SSL port without --tls?";
};
vlog3(Dumper($json));

defined($json->{"status"}) or quit "UNKNOWN", "worksheet status not returned. $nagios_plugins_support_msg_api";
defined($json->{"jobstatusString"}) or quit "UNKNOWN", "worksheet status string not returned. $nagios_plugins_support_msg_api";
my $jobStatus = $json->{"status"};
my $jobstatusString = $json->{"jobstatusString"};
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
