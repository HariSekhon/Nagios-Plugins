#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/events_alerts.html#events-alerts

$DESCRIPTION = "Nagios Plugin to check DataStax OpsCenter alerts for a given cluster via the DataStax OpsCenter Rest API

Requires the DataStax Enterprise

Tested on DataStax OpsCenter 5.0.0 with DataStax Enterprise Server 4.5.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use Data::Dumper;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

$json = curl_opscenter "$cluster/alerts/fired";
vlog3 Dumper($json);

isArray($json) or quit "UNKNOWN", "non-array returned. $nagios_plugins_support_msg_api";

# TODO: Improve this when I actually have some alerts to evaluate
if(@{$json}){
    critical;
    $msg .= scalar @{$json} . " ";
} else {
    $msg .= "no ";
}
$msg .= "alerts fired in DataStax OpsCenter for cluster '$cluster'";

vlog2;
quit $status, $msg;
