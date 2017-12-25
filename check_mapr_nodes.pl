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

$DESCRIPTION = "Nagios Plugin to check the number of MapR nodes managed or in a given cluster via the MapR Control System REST API

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %thresholdoptions,
);

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster $cluster if $cluster;
validate_thresholds(0, 0, { "simple" => "lower", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/node/list?columns=health,healthDesc";
$url .= "&cluster=$cluster" if $cluster;
$json = curl_mapr $url, $user, $password;

my $total_nodes = get_field_int("total");
if($total_nodes == 0){
    quit "CRITICAL", "no nodes found, did you specify the correct --cluster? See --list-clusters";
}
plural $total_nodes;
$msg = $total_nodes . " MapR node$plural found";
check_thresholds($total_nodes);
$msg .= " | 'MapR nodes'=" . $total_nodes;
msg_perf_thresholds();

vlog2;
quit $status, $msg;
