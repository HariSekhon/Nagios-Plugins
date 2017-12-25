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

$DESCRIPTION = "Nagios Plugin to check the MapR cluster version of a given cluster or all clusters managed by MapR Control System via the MapR Control System REST API

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

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

my $expected;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    "e|expected=s"      =>  [ \$expected, "Expected version regex (optional)" ],
);
splice @usage_order, 7, 0, 'expected';

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;

my $expected_regex = validate_regex($expected) if defined($expected);

vlog2;
set_timeout();

$status = "OK";

$json = curl_mapr "/dashboard/info", $user, $password;

my @data = get_field_array("data");

my $name;
my $version;
my $found;
foreach(@data){
    $name = get_field2($_, "cluster.name");
    next if $cluster and $name ne $cluster;
    $found++;
    $version = get_field2($_, "version");
    $msg = "cluster '$name' version $version";
    if(defined($expected_regex)){
        unless($version =~ $expected_regex){
            critical;
            $msg .= " (expected: '$expected')";
        }
    }
    $msg .= ", ";
}
$msg =~ s/, $//;
unless($found){
    quit "UNKNOWN", "cluster not found, did you specify a valid cluster name? See --list-clusters";
}

vlog2;
quit $status, $msg;
