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

Outputs various details such as leader, version and activated/deactivated slaves (with perfdata). Also outputs uptime if using --verbose

Tested on Mesos 0.23 and 0.24";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use Data::Dumper;
use LWP::Simple '$ua';

set_port_default(5050);

env_creds(["Mesos Master", "Mesos"], "Mesos");

%options = (
    %hostoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

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

#if(not defined($json->{"cluster"})){
#    quit "UNKNOWN", "cluster field not found, did you query a Mesos slave or some other service instead of the Mesos master?";
#}
my $cluster             = get_field("cluster", 1);
my $leader              = get_field("leader");
my $version             = get_field("version");
my $start_time          = get_field_float("start_time");
my $activated_slaves    = get_field_int("activated_slaves");
my $deactivated_slaves  = get_field_int("deactivated_slaves");

my $uptime_secs = int(time - $start_time);
my $human_time  = sec2human($uptime_secs);

$msg = "Mesos";
if($cluster){
    $msg .= " cluster '$cluster'";
}
$msg .= " leader '$leader', activated_slaves=$activated_slaves, deactivated_slaves=$deactivated_slaves, version '$version'";
$msg .= " started $human_time ago ($uptime_secs secs)" if $verbose;
$msg .= " | activated_slaves=$activated_slaves deactivated_slaves=$deactivated_slaves";

quit $status, $msg;
