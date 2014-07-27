#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-07-27 22:44:19 +0100 (Sun, 27 Jul 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Hadoop config staleness via Ambari REST API

Tested on Hortonworks HDP 2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;
use Data::Dumper;

$ua->agent("Hari Sekhon $progname $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;

validate_thresholds();
validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "http://$host:$port$api";

list_ambari_components();

cluster_required();
# TODO: this needs to be documented better in the github v1 API doc
$json = curl_ambari "$url_prefix/clusters/$cluster/host_components?fields=HostRoles/component_name&HostRoles/stale_configs=true";
my @items = get_field_array("items");
if(@items){
    $msg = "stale host component configs found for: ";
    foreach(@items){
        $msg .= get_field2($_, "HostRoles.component_name") . ", ";
    }
    $msg =~ s/, $//;
} else {
    $msg = "no stale host component configs found";
}

vlog2;
quit $status, $msg;
