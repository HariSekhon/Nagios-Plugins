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

Tested against Datameer 2.1.4.6 and 3.0.11";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS;
use LWP::Simple '$ua';
use Time::Local;

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $default_port = 8080;
$port = $default_port;

my $default_warning  = 31;
my $default_critical = 15;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold in days (default: $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in days (default: $default_critical)" ],
);

@usage_order = qw/host port user password warning critical/;

env_creds("DATAMEER");

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds(1, 1, { "simple" => "lower", "positive" => 1} );

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();

$status = "OK";

my $content = curl $url, $user, $password;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

unless(defined($json->{"LicenseExpirationDate"})){
    quit "UNKNOWN", "LicenseExpirationDate was not defined in json output returned from Datameer server. Format may have changed. $nagios_plugins_support_msg";
}
my $expiry_date = $json->{"LicenseExpirationDate"};

unless($expiry_date =~ /^(\w{3})\s+(\d{1,2}),\s+(\d{4})\s+(\d{1,2}):(\d{2}):(\d{2})\s+([AP]M)$/){
    quit "UNKNOWN", "failed to recognize expiry date format retrieved from Datameer server. Format may have changed or date may be invalid. $nagios_plugins_support_msg";
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

# Lifted from check_ssl_cert.pl, TODO: move to lib
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

my $expiry    = timegm($sec, $min, $hour, $day, $months{$month}, $year-1900) || quit "UNKNOWN", "Failed to convert timestamp $year-$months{$month}-$day $hour:$min:$sec";
my $now       = time || code_error "Failed to get epoch timestamp. $nagios_plugins_support_msg";
my $days_left = int( ($expiry - $now) / (86400) );
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
