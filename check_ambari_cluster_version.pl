#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-11-26 19:44:32 +0000 (Thu, 26 Nov 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check an Ambari managed Cluster is on the right HDP version via Ambari REST API

Tested on Ambari 2.1.0, 2.1.2, 2.2.1, 2.5.1 on Hortonworks HDP 2.2, 2.3, 2.4, 2.6";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Ambari;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected;

%options = (
    %hostoptions,
    %useroptions,
    %ambari_options,
    "e|expected=s" => [ \$expected, "Expected version string (optional). This can be any string since Ambari can technically support any stack, not just HDP. This string must match exactly, eg. 'HDP-2.3', not '2.3' or 'HDP2.3'" ],
);
splice @usage_order, 7, 0, qw/expected/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$cluster    = validate_ambari_cluster($cluster) if $cluster;

validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

$msg = "Ambari cluster '$cluster' version = ";
$json = curl_ambari "$url_prefix/clusters/$cluster?fields=Clusters/version";
my $version = get_field("Clusters.version");
$msg .= "'$version'";
if(defined($expected) and $version ne $expected){
    critical;
    $msg .= " (expected '$expected')";
}

vlog2;
quit $status, $msg;
