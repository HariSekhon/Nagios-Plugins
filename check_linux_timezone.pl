#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-12-07 14:52:59 +0000 (Wed, 07 Dec 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# No longer checking /etc/sysconfig/clock as it's been removed from RHEL7:
#
# https://github.com/harisekhon/nagios-plugins/issues/66

$DESCRIPTION = "Nagios Plugin to check a Linux Server's timezone is set as expected";

$VERSION = "0.9.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $timezone;
my $alternate_timezone;
my $localtime_file  = "/etc/localtime";
#my $sysconfig_clock = "/etc/sysconfig/clock";
my $zoneinfo_file;
my $zoneinfo_dir    = "/usr/share/zoneinfo";
#my $no_warn_symlinks;

%options = (
    "T|timezone=s"       => [ \$timezone,           "Timezone to expect the server in as shown by the 'date' command (eg. GMT)" ],
    "A|alternate=s"      => [ \$alternate_timezone, "Alternative timezone to expect the server in. Optional (defaults to same as --timezone). Useful to allow daylight saving time shifts by specifying a second timezone to allow (eg. BST)" ],
    "Z|zoneinfo-file=s"  => [ \$zoneinfo_file,      "Timezone file to compare $localtime_file to. Optional (defaults to --timezone suffixed to $zoneinfo_dir). Useful when your localtime is set to say Europe/London which shows up as GMT/BST but you still want to validate that $localtime_file is set to Europe/London for following daylight saving time changes back and forth. Can be any valid timezone file under $zoneinfo_dir/ (eg. UTC or GMT) or a fully qualified path to a timezone file" ],
    #"no-warn-symlinks"   => [ \$no_warn_symlinks,   "Do not warn on detecting symlinks for $localtime_file or $sysconfig_clock" ],
);
@usage_order = qw/timezone alternate zoneinfo-file no-warn-symlinks/;

get_options();
# Only tested on Linux + Mac - you can comment out this next line if you want to test it on another unix variant
linux_mac_only();

$status = "OK";

defined($timezone) || usage "timezone not specified";
$timezone =~ /^[\w\/\+-]+$/ || usage "invalid timezone specified";
$zoneinfo_file = $timezone unless defined($zoneinfo_file);
$alternate_timezone = $timezone unless defined($alternate_timezone);
unless(isPathQualified($zoneinfo_file)){
    $zoneinfo_file = "$zoneinfo_dir/$zoneinfo_file";
}
$zoneinfo_file = validate_filename($zoneinfo_file);

set_timeout();

vlog2 "getting current timezone\n";
my $server_timezone = join("\n", cmd("/bin/date +%Z"));
quit "CRITICAL", "failed to get timezone" unless $server_timezone;
$msg = "timezone is '$server_timezone'";
unless("$server_timezone" eq "$timezone" or "$server_timezone" eq "$alternate_timezone"){
    critical;
    if($timezone ne $alternate_timezone){
        $msg .= " (expected: '$timezone' or '$alternate_timezone')";
    } else {
        $msg .= " (expected: '$timezone')";
    }
    quit "CRITICAL", $msg;
}

# Alpine Linux doesn't have zoneinfo
vlog2 "checking $localtime_file against $zoneinfo_file";
my $fh1 = open_file($localtime_file);
if(-f $zoneinfo_file){
    my $fh2 = open_file($zoneinfo_file);
    my $linecount = 0;
    while(<$fh1>){
        unless($_ eq <$fh2>){
            quit "CRITICAL", "$msg, localtime file '$localtime_file' does not match timezone file '$zoneinfo_file'!";
        }
        $linecount++;
        # the largest file under /usr/share/zoneinfo is 119 lines /usr/share/zoneinfo/right/Atlantic/Madeira
        if($linecount > 150){
            quit "CRITICAL", "$msg, localtime file '$localtime_file' exceeded 150 lines, aborting check!";
        }
    }
    if(<$fh2>){
        quit "CRITICAL", "$msg, localtime file '$localtime_file' does not match timezone file '$zoneinfo_file' (zoneinfo file is larger)!";
    }
    close $fh2;
} else {
    warning;
    $msg .= ". Zoneinfo file '$zoneinfo_file' not found! You may need to specify the path manually using --zoneinfo-file (if you don't have a zoneinfo installation because you're on a minimal docker distribution like Alpine then you can set --zoneinfo-file to /etc/localtime to avoid this error)"
}
close $fh1;

# let open_file handle the validation
#unless( -r $sysconfig_clock){
#    warning;
#    $msg .= "unable to read file '$sysconfig_clock'! $msg";
#}
#vlog2 "checking $sysconfig_clock";
#my $fh3 = open_file($sysconfig_clock);
#while(<$fh3>){
#    chomp;
#    vlog3 "$sysconfig_clock: $_";
#    if(/^\s*ZONE\s*=\s*"?(.+?)"?\s*$/){
#        unless($1 eq $timezone){
#            critical;
#            if($verbose or not $timezone_mismatch){
#                $msg = "$sysconfig_clock incorrectly configured (expected: '$timezone', got: '$1')! $msg";
#            }
#            last;
#        }
#    }
#}
#close $fh3;

#my $symlinks_found = 0;
#foreach(($localtime_file, $sysconfig_clock)){
#    if ( -l $_ ){
#        $symlinks_found = 1;
#        if($verbose or not $no_warn_symlinks){
#            $msg .= ", '$_' is a symlink";
#        }
#    }
#}
#if($symlinks_found and not $no_warn_symlinks){
#    warning;
#    $msg .= "!";
#}

quit $status, $msg;
