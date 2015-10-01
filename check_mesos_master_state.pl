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

$DESCRIPTION = "Nagios Plugin to check Mesos Master state via Rest API

Tested on Mesos 0.23 and 0.24";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';

env_creds(["Mesos Master", "Mesos"], "Mesos");
set_port_default(5050);

%options = (
    %hostoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);

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

my $cluster = get_field("cluster");
my $leader  = get_field("leader");
my $activated_slaves = get_field_int("activated_slaves");
my $version = get_field("version");
my $deactivated_slaves = get_field_int("deactivated_slaves");

$msg = "cluster '$cluster' leader '$leader', activated_slaves=$activated_slaves, deactivated_slaves=$deactivated_slaves, version '$version' | activated_slaves=$activated_slaves deactivated_slaves=$deactivated_slaves";

quit $status, $msg;
