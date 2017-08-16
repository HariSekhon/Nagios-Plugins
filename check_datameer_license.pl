#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:47:10 +0000 (Wed, 27 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check Datameer license expiry using the Datameer Rest API

Also checks that the license mode is set to 'Enterprise' rather than 'Evaluation' or other, and also that the license start date isn't in the future

Tested against Datameer 2.1.4.6, 3.0.11 and 3.1.1";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;
use JSON::XS;
use LWP::Simple '$ua';
use POSIX qw/floor ceil/;
use Time::Local;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $default_warning  = 31;
my $default_critical = 15;

$warning  = $default_warning;
$critical = $default_critical;

my $license_enterprise = "Enterprise";
my $license_evaluation = "Evaluation";
my $evaluation = 0;

%options = (
    %datameer_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold in days (default: $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in days (default: $default_critical)" ],
    "evaluation"       => [ \$evaluation,   "Allows Evaluation license, otherwise raises critical for anything other than Enterprise. Don't use this after you take Datameer in to production" ],
);

@usage_order = qw/host port user password warning critical/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
validate_thresholds(1, 1, { "simple" => "lower", "positive" => 1 } );

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

my $json = datameer_curl $url, $user, $password;

foreach(qw/LicenseStartDate LicenseExpirationDate LicenseType/){
    unless(defined($json->{$_})){
        quit "UNKNOWN", "$_ was not defined in json output returned from Datameer server. API may have changed. $nagios_plugins_support_msg";
    }
}
my $start_date   = $json->{"LicenseStartDate"};
my $expiry_date  = $json->{"LicenseExpirationDate"};
my $license_type = $json->{"LicenseType"};

vlog2 "License Type: $license_type";
vlog2 "Start  Date:  $start_date";
vlog2 "Expiry Date:  $expiry_date\n";

# ============================================================================ #
# Check License mode

if($license_type eq $license_enterprise){
    # OK
} elsif($evaluation and $license_type eq $license_evaluation){
    # OK if --evaluation
} else {
    critical;
    $msg .= "License type = '$license_type', expected '$license_enterprise'. ";
}

# ============================================================================ #
# Check Start Date

unless($start_date =~ /^(\w{3})\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s+([AP]M)$/){
    quit "UNKNOWN", "failed to recognize start date format retrieved from Datameer server. API format may have changed or date may be invalid. $nagios_plugins_support_msg";
}
my $month = $1;
my $day   = $2;
my $year  = $3;
my $hour  = $4;
my $min   = $5;
my $sec   = $6;
if($7 eq "PM"){
    $hour += 12 if $hour < 12;
}

my $starting_in_days = timecomponents2days($year, $month, $day, $hour, $min, $sec);
vlog2 sprintf("calculated license start date as %.1f days (should be negative)\n", $starting_in_days);
if($starting_in_days >= 0){
    critical;
    $msg .= "license start date is in the future! ";
}

# ============================================================================ #
# Check Expiry

unless($expiry_date =~ /^(\w{3})\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s+([AP]M)$/){
    quit "UNKNOWN", "failed to recognize expiry date format retrieved from Datameer server. API format may have changed or date may be invalid. $nagios_plugins_support_msg";
}
$month = $1;
$day   = $2;
$year  = $3;
$hour  = $4;
$min   = $5;
$sec   = $6;
if($7 eq "PM"){
    $hour += 12 if $hour < 12;
}

my $days_left = floor(timecomponents2days($year, $month, $day, $hour, $min, $sec));
isInt($days_left, 1) or code_error "non-integer returned for days left calculation. $nagios_plugins_support_msg";

vlog2 "calculated $days_left days left on license\n";

plural abs($days_left);
if($days_left < 0){
    critical;
    $days_left = abs($days_left);
    $msg .= "Datameer LICENSE EXPIRED $days_left day$plural ago'. Expiry Date: '$expiry_date'";
} else {
    $msg .= "$days_left day$plural remaining on Datameer license";
    $msg .= " ($license_type)" if($evaluation and $license_type eq $license_evaluation);
    $msg .= ". License Expires: '$expiry_date'";
    check_thresholds($days_left);
}

quit $status, $msg;
