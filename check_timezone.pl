#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-12-07 14:52:59 +0000 (Wed, 07 Dec 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Linux Server's timezone is set as expected";

$VERSION = "0.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $timezone_file;
my $localtime_file = "/etc/localtime";
my $timezone;
my $etc_localtime;
my $alternate_timezone;
my $timezone_dir = "/usr/share/zoneinfo";
my $sysconfig_clock = "/etc/sysconfig/clock";

%options = (
    "T|timezone=s"       => [ \$timezone,           "Timezone to expect the server in. Required (can be any valid timezone from $timezone_dir/ eg. UTC or GMT)" ],
    "A|alternate=s"      => [ \$alternate_timezone, "Alternative timezone to expect the server in. Optional (defaults to timezone). Useful to allowing BST daylight saving time shifts by specifying a second timezone to allow (eg BST)" ],
    "L|localtime-file=s" => [ \$etc_localtime,      "Timezone file to compare $localtime_file and $sysconfig_clock to. Optional (defaults to timezone). Useful when your localtime is set to say Europe/London which shows up as GMT but you still want to validate that $localtime_file is set to Europe/London for following DST changes. (Can be any valid timezone file under $timezone_dir/ eg. UTC or GMT)" ],
);
@usage_order = qw/timezone alternate localtime-time/;

get_options();
linux_only();

$status = "OK";

defined($timezone) || usage "timezone not specified";
$timezone =~ /^[\w\/\+-]+$/ || usage "invalid timezone specified";
$etc_localtime = $timezone unless defined($etc_localtime);
$alternate_timezone = $timezone unless defined($alternate_timezone);
$timezone_file = "$timezone_dir/$etc_localtime";
$timezone_file = validate_filename($timezone_file);
( -f "$timezone_dir/$timezone" ) || usage "timezone does not appear to be valid, timezone file '$timezone_file' not found";
( -f "$timezone_file" ) || usage "localtime file does not appear to be valid, timezone file '$timezone_file' not found";

set_timeout();

vlog2 "getting current timezone\n";
my $server_timezone = join("\n", cmd("/bin/date +%Z"));
quit "CRITICAL", "failed to get timezone" unless $server_timezone;
my $timezone_mismatch = 0;
$msg = "timezone is '$server_timezone'";
unless("$server_timezone" eq "$timezone" or "$server_timezone" eq "$alternate_timezone"){
    critical;
    if($timezone ne $alternate_timezone){
        $msg .= " (expected: '$timezone' or '$alternate_timezone')";
    } else {
        $msg .= " (expected: '$timezone')";
    }
    $timezone_mismatch = 1;
}

vlog2 "checking $localtime_file against $timezone_file";
my $fh1 = open_file($localtime_file);
my $fh2 = open_file($timezone_file);
my $linecount = 0;
while(<$fh1>){
    unless($_ eq <$fh2>){
        critical;
        if($verbose and not $timezone_mismatch){
            $msg .= ", localtime file '$localtime_file' does not match timezone file '$timezone_file'";
            last;
        }
    }
    $linecount++;
    if($linecount > 10){
        warning;
        $msg .= ", localtime file '$localtime_file' exceeded 10 lines, aborting check";
    }
}
close $fh1;
close $fh2;

unless( -r $sysconfig_clock){
    warning;
    $msg .= ", unable to read file '$sysconfig_clock'";
}
vlog2 "checking $sysconfig_clock";
my $fh3 = open_file($sysconfig_clock);
while(<$fh3>){
    chomp;
    vlog3 "$sysconfig_clock: $_";
    if(/^\s*ZONE\s*=\s*"?(.+?)"?\s*$/){
        unless($1 eq $etc_localtime){
            critical;
            if($verbose or not $timezone_mismatch){
                $msg .= ", $sysconfig_clock incorrectly configured (expected: '$etc_localtime', got: '$1')";
            }
            last;
        }
    }
}
close $fh3;

foreach(($localtime_file, $sysconfig_clock)){
    if ( -l $_ ){
        warning;
        $msg .= ", '$_' is a symlink!";
    }
}

quit $status, $msg;
