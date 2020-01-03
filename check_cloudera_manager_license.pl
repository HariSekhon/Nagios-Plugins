#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-12 22:33:14 +0100 (Sat, 12 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Cloudera Manager license expiry using CM API

Calculates the number of days left on license and compares against given thresholds

Also checks if the license is running free version either 'Cloudera Standard' or 'Cloudera Express' and if the license is in Trial Mode

Tested on Cloudera Manager 4.8.2, 5.0.0, 5.7.0, 5.10.0, 5.12.0";

$VERSION = "0.1.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(31, 15);

my $license_free;
my $license_trial;

%options = (
    %hostoptions,
    %useroptions,
    %cm_options_tls,
    "F|license-free"    =>  [ \$license_free,   "Free  License OK - Cloudera Standard or Cloudera Express - CM reverts to this after commercial license expiry (default: CRITICAL)" ],
    "A|license-trial"   =>  [ \$license_trial,  "Trial License OK (default: WARNING)" ],
    "w|warning=s"       =>  [ \$warning,        "Warning  threshold in days (default: $default_warning)"  ],
    "c|critical=s"      =>  [ \$critical,       "Critical threshold in days (default: $default_critical)" ],
);

@usage_order = qw/host port user password tls ssl-CA-path tls-noverify license-free license-trial warning critical/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds(1, 1, { "simple" => "lower", "positive" => 1 } );

vlog2;
set_timeout();

$status = "OK";

$url = "$api/cm/license";
try{
    cm_query();
};
catch{
    if($@ =~ /This installation is currently running (Cloudera (?:Standard|Express))/){
        $msg = "licensed as $1";
        if($license_free){
            $status = "OK"
        } else {
            $msg .= " (Commercial license expired? Use --license-free if intentionally using free version)";
        }
    } else {
        critical;
        $msg = $@;
    }
    quit $status, $msg;
};
foreach(qw/owner expiration/){
    unless(defined($json->{$_})){
        quit "UNKNOWN", "$_ field not found in returned license information. $nagios_plugins_support_msg_api";
    }
}
if($json->{"owner"} eq "Trial License"){
    if($license_trial){
        $msg = "trial license, ";
    } else {
        warning;
        $msg = "TRIAL license (use --license-trial if this is ok), ";
    }
}
unless($json->{"expiration"} =~ /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})\.\d+[A-Za-z]?$/){
    quit "UNKNOWN", "failed to recognize expiry date format retrieved from Cloudera Manager. API format may have changed or date may be invalid. $nagios_plugins_support_msg";
}
my $year  = $1;
my $month = $2;
my $day   = $3;
my $hour  = $4;
my $min   = $5;
my $sec   = $6;
my $days_left = floor(timecomponents2days($year, $month, $day, $hour, $min, $sec));
isInt($days_left, 1) or code_error "non-integer returned for days left calculation. $nagios_plugins_support_msg";
vlog2 "calculated $days_left days left on license\n";
plural abs($days_left);
if($days_left < 0){
    critical;
    $days_left = abs($days_left);
    $msg .= "Cloudera Manager LICENSE EXPIRED $days_left day$plural ago'. Expiry Date: '" . $json->{"expiration"} . "'";
} else {
    $msg .= "$days_left day$plural remaining on Cloudera Manager license";
    $msg .= ". License Expires: '" . $json->{"expiration"} . "'";
    check_thresholds($days_left);
}

quit $status, $msg;
