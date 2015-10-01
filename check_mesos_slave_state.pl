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

$DESCRIPTION = "Nagios Plugin to check Mesos Slave state via Rest API

Outputs master, cpu/mem/disk/port resources and perfdata, version and also optionally uptime if using --verbose

Tested on Mesos 0.23 and 0.24";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use Data::Dumper;
use LWP::Simple '$ua';

env_creds(["Mesos Slave", "Mesos"], "Mesos");
set_port_default(5051);

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
$json = curl_json $url, "Mesos Slave state";
vlog3 Dumper($json);

my $master     = get_field("master_hostname");
my $version    = get_field("version");
my $start_time = get_field_float("start_time");
my $mem        = get_field_int("resources.mem");
my $cpus       = get_field_int("resources.cpus");
my $disk       = get_field_int("resources.disk");
my $ports      = get_field("resources.ports");

my $mem_human  = human_units($mem,  "MB");
my $disk_human = human_units($disk, "MB");

my $uptime_secs = int(time - $start_time);
my $human_time  = sec2human($uptime_secs);

$msg = "Mesos slave, master='$master', cpus=$cpus, mem=$mem_human";
#$msg .= "($mem)" if $verbose;
$msg .= ", disk=$disk_human";
#$msg .= "($disk)" if $verbose;
$msg .= ", ports='$ports', version '$version'";
$msg .= " started $human_time ago ($uptime_secs secs)" if $verbose;
$msg .= " | cpus=$cpus mem=${mem}MB disk=${disk}MB";

quit $status, $msg;
