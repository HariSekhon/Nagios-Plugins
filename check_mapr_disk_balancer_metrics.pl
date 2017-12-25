#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-15 23:54:05 +0100 (Mon, 15 Sep 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to fetch the MapR-FS Balancer metrics via the maprcli command. Call over NRPE.

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $maprcli = "maprcli";

%options = (
    "m|maprcli=s"   => [ \$maprcli, "Path to 'maprcli' command if not in \$PATH ($ENV{PATH})" ],
);
splice @usage_order, 6, 0, qw/maprcli/;

get_options();

$maprcli = validate_program_path($maprcli, "maprcli");

vlog2;
set_timeout();

$status = "OK";

my $cmd = "$maprcli dump balancermetrics -json";
my @output = cmd($cmd, 1);
$json = join(" ", @output);
$json = isJson($json) or quit "UNKNOWN", "invalid json returned by command '$cmd'";

my $numContainersMoved  = get_field_int("data.0.numContainersMoved");
my $numMBMoved          = get_field_int("data.0.numMBMoved");
my $timeOfLastMove      = get_field("data.0.timeOfLastMove", 1);

$msg = "MapR-FS balancer containers moved = $numContainersMoved, volume moved = " . human_units($numMBMoved * 1024 * 1024);
$msg .= ", time of last move = '$timeOfLastMove'" if $timeOfLastMove;
$msg .= " | containers_moved=${numContainersMoved}c volume_moved=${numMBMoved}MB";

vlog2;
quit $status, $msg;
