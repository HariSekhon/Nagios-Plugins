#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-15 23:54:16 +0100 (Mon, 15 Sep 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check the status of the MapR Role Balancer via the maprcli command

Tested on MapR 4.0.1";

$VERSION = "0.2";

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

my $cmd = "$maprcli dump rolebalancerinfo -json";
my @output = cmd($cmd);
foreach(@output){
    /No active role switches/ and quit "OK", $_;
}
$json = join(" ", @output);
$json = isJson($json) or quit "UNKNOWN", "invalid json returned by command '$cmd'";

my $balancer_status       = get_field("status");
my $containerid           = get_field_int("containerid");
my $Tail_IP_Port          = get_field("Tail IP:Port");
my $Updates_blocked_since = get_field("Updates blocked Since");

critical unless $balancer_status eq "OK";

$msg = "role balancer status '$balancer_status': $containerid = $containerid, tail IP:Port = '$Tail_IP_Port', updates blocked since: '$Updates_blocked_since'";

quit $status, $msg;
