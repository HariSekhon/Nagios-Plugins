#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-11-13 19:17:54 +0000 (Tue, 13 Nov 2012)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check for NetAcuity license expiry warnings";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

# "The NetAcuity license key for CBSA DB, feature code 19 will expire within 20 days."
# This is a very lax regex for me but it is more likely to catch the log line should the grammar/format change
my $license_expire_regex = qr/\blicen[sc]e\b.*\bexpir.*\s+(\d+)\s+((?:day|hour|min(?:ute)?)s?)/io;

my $default_logfile  = "/usr/local/NetAcuity/server/netacuity.log";
my $default_warning  = "30"; # days
my $default_critical = "10"; # days
my $min_threshold    = 7;    # days. Don't let user set threshold lower than this

my $logfile          = $default_logfile;
$warning             = $default_warning;
$critical            = $default_critical;

my $license_num;
my $license_units;

%options = (
    "l|logfile=s"      => [ \$logfile,      "NetAcuity log file (defaults to $default_logfile)" ],
    "w|warning=s"      => [ \$warning,      "Warning threshold in days"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in days" ],
);
@usage_order = qw/logfile warning critical/;

get_options();
$logfile = validate_filename($logfile);
validate_thresholds(1, 1, { "simple" => "lower", "integer" => 1 });

if($thresholds{"warning"}{"lower"}  < $min_threshold or
   $thresholds{"critical"}{"lower"} < $min_threshold){
    usage "thresholds too low, cannot be less than $min_threshold!";
}

vlog2;
set_timeout();

$status = "OK";
my $fh = open_file $logfile;
while(<$fh>){
    if($_ =~ $license_expire_regex){
        if(defined($license_num)){
            if($1 < $license_num and $2 eq "days"){
                $license_num = $1
            }
        } else {
            $license_num   = $1;
            $license_units = $2;
        }
    } elsif(/expired/io){
        quit "CRITICAL", $_;
    }
}
$status = "OK";
if(!defined($license_num)){
    $msg = "NetAcuity license ok, no warnings in $logfile";
} else {
    $msg    = "NetAcuity license expires in $license_num $license_units";
    if($license_units =~ /day/){
        check_thresholds($license_num);
    } else {
        critical;
        $msg .= " (w=$thresholds{warning}{lower}/c=$thresholds{critical}{lower} days)";
    }
}

quit $status, $msg;
