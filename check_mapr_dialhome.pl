#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-10-05 20:02:20 +0100 (Sun, 05 Oct 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check MapR's dialhome settings using the MapR Control System REST API

If dialhome is enabled, checks that MapR has dialed home within the last N number of days (default: 7)

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expect_enabled;
my $expect_disabled;
my $last_dialed_days = 7;

%options = (
    %mapr_options,
    "enabled"       => [ \$expect_enabled,   "Expected enabled"  ],
    "disabled"      => [ \$expect_disabled,  "Expected disabled" ],
    "last-dialed=s" => [ \$last_dialed_days, "Check dialed home within this number of days (default: 7)" ],
);
splice @usage_order, 6, 0, qw/enabled disabled last-dialed/;

get_options();

validate_mapr_options();
usage "--enabled/--disabled are mutually exclusive" if ($expect_enabled and $expect_disabled);
validate_int($last_dialed_days, "last dialed days", 1, 30);

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/dialhome/status", $user, $password;

my $enabled = get_field("data.0.enabled");
my $last_dialed;
my $last_dialed_string = "unknown";
# these give 404 when dialhome is not enabled
if($enabled){
    $json = curl_mapr "/dialhome/lastdialed", $user, $password;
    $last_dialed = get_field("data.0.date");
    if($last_dialed > 2000000000){
        warning;
        $last_dialed_string = "never";
    } else {
        $last_dialed_string = localtime $last_dialed;
        if($last_dialed > time){
            warning;
            $last_dialed_string .= " (in future! NTP issue?)";
        } elsif($last_dialed < (time - ( $last_dialed_days * 86400 ))){
            warning;
            $last_dialed_string .= " (more than $last_dialed_days days ago!)";
        }
    }
    # status='ERROR'. No metrics founds for the given day
    #$json = curl_mapr "/dialhome/metrics", $user, $password;
}

$msg = "MapR dialhome is " . ($enabled ? "" : "not ") . "enabled";

if($enabled){
    if($expect_disabled){
        critical;
        $msg .= " (expected disabled)";
    }
    $msg .= ", last dialed home: $last_dialed_string";
} elsif($expect_enabled and not $enabled){
    critical;
    $msg .= " (expected enabled)";
}

quit $status, $msg;
