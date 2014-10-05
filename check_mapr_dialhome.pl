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

Tested on MapR 3.1.0 and 4.0.1";

$VERSION = "0.1";

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

%options = (
    %mapr_options,
    "enabled"    => [ \$expect_enabled,  "Expected enabled"  ],
    "disabled"   => [ \$expect_disabled, "Expected disabled" ],
);
splice @usage_order, 6, 0, qw/enabled disabled/;

get_options();

validate_mapr_options();
usage "--enabled/--disabled are mutually exclusive" if ($expect_enabled and $expect_disabled);

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/dialhome/status", $user, $password;

my $enabled = get_field("data.0.enabled");
my $last_dialed;
# these give 404 when dialhome is not enabled
if($enabled){
    $json = curl_mapr "/dialhome/lastdialed", $user, $password;
    $last_dialed = get_field("data.0.date");
    if($last_dialed = 1392768000000){
        $last_dialed = "never";
    } else {
        $last_dialed = localtime $last_dialed;
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
    $msg .= ", last dialed home: $last_dialed";
} elsif($expect_enabled and not $enabled){
    critical;
    $msg .= " (expected enabled)";
}

quit $status, $msg;
