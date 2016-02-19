#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-09-30 16:49:15 +0100 (Wed, 30 Sep 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check the number of Mesos activated slaves via the Mesos Master Rest API

Tested on Mesos 0.23 and 0.24";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';

set_port_default(5050);
set_threshold_defaults(1, 1);

env_creds(["Mesos Master", "Mesos"], "Mesos");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(1, 1, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1 } );

vlog2;
set_timeout();

$status = "OK";

# /api/v1/admin is coming in 1.0
#         executor
#         scheduler
#         internal
my $url = "http://$host:$port/state.json";
$json = curl_json $url, "Mesos Master state";
vlog3 Dumper($json);

my $cluster = get_field("cluster", 1);
my $activated_slaves = get_field_int("activated_slaves");

$msg = "Mesos";
if($cluster){
    $msg .= " cluster '$cluster'";
}
$msg .= " activated_slaves=$activated_slaves";
check_thresholds($activated_slaves);
$msg .= " | activated_slaves=$activated_slaves";
msg_perf_thresholds(0, 'lower');

vlog2;
quit $status, $msg;
