#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:47:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check Datameer license expiry using the Datameer Rest API

Also checks that the license mode is set to 'Enterprise'

Tested against Datameer 2.1.4.6 and 3.0.11";

$VERSION = "0.2";

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
use Time::Local;

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $default_warning  = 31;
my $default_critical = 15;

$warning  = $default_warning;
$critical = $default_critical;

my $trial = 0;

%options = (
    %datameer_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold in days (default: $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in days (default: $default_critical)" ],
    "l|trial-license"  => [ \$trial,        "Allows trial license, otherwise raises critical. Don't use this after you take Datameer in to production" ],
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

# ============================================================================ #
# Check License mode

if($license_type eq "Enterprise"){
    # OK
} elsif($trial and $license_type eq "Trial"){
    # OK if --trial-license
} else {
    critical;
    $msg .= "License type = '$license_type', expected 'Enterprise'. ";
}

# TODO: move to lib and reintegrate with check_ssl_cert.pl
sub month2int($){
    my $month = shift;
    defined($month) or code_error "no arg passed to month2int";
    my %months = (
        "Jan" => 0,
        "Feb" => 1,
        "Mar" => 2,
        "Apr" => 3,
        "May" => 4,
        "Jun" => 5,
        "Jul" => 6,
        "Aug" => 7,
        "Sep" => 8,
        "Oct" => 9,
        "Nov" => 10,
        "Dec" => 11
    );
    grep { $month eq $_ } keys %months or code_error "non-month passed to month2int()";
    return $months{$month};
}

sub timecomponents2days($$$$$$){
    my $year  = shift;
    my $month = shift;
    my $day   = shift;
    my $hour  = shift;
    my $min   = shift;
    my $sec   = shift;
    my $month_int;
    if(isInt($month)){
        $month_int = $month;
    } else {
        $month_int = month2int($month);
    }
    my $epoch = timegm($sec, $min, $hour, $day, $month_int, $year-1900) || code_error "failed to convert timestamp $year-$month-$day $hour:$min:$sec";
    my $now   = time || code_error "failed to get epoch timestamp";
    return int( ($epoch - $now) / (86400) );
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

my $epoch = timegm($sec, $min, $hour, $day, month2int($month), $year-1900) || code_error "failed to convert timestamp $year-$month-$day $hour:$min:$sec";
my $now   = time || code_error "failed to get epoch timestamp";
if($epoch > $now){
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

my $days_left = timecomponents2days($year, $month, $day, $hour, $min, $sec);
isInt($days_left, 1) or code_error "non-integer returned for days left calculation. $nagios_plugins_support_msg";

plural abs($days_left);
if($days_left < 0){
    critical;
    $days_left = abs($days_left);
    $msg .= "Datameer LICENSE EXPIRED $days_left day$plural ago'. Expiry Date: '$expiry_date'";
} else { 
    $msg .= "$days_left day$plural remaining on Datameer license. License Expires: '$expiry_date'";
    check_thresholds($days_left);
}

vlog2;
quit $status, $msg;
