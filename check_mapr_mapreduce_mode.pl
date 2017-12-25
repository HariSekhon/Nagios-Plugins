#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check the default MapReduce mode on a MapR Hadoop cluster via the MapR Control System REST API

Requires MapR 4.0 onwards, will get a '404 Not Found' on MapR 3.1 and earlier where this API endpoint isn't implemented.

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

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

my $expected;

%options = (
    %mapr_options,
    "M|mode=s" => [ \$expected, "Expected MapReduce mode ('yarn' or 'classic')" ],
);
splice @usage_order, 6, 0, 'mode';

get_options();

validate_mapr_options();
if($expected){
    $expected eq "yarn" or $expected eq "classic" or usage "--mode to expect must be either 'yarn' or 'classic'";
}

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/cluster/mapreduce/get", $user, $password;

my @data = get_field_array("data");

foreach(@data){
    my $mode = get_field2($_, "default_mode");
    $msg .= "default mapreduce mode '$mode'";
    if(defined($expected) and $mode ne $expected){
        critical;
        $msg .= " (expected: $expected)";
    }
    $msg .= ", mapreduce version " . get_field2($_, "mapreduce_version") . ", ";
}
$msg =~ s/, $//;

vlog2;
quit $status, $msg;
