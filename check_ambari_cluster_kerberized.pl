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

$DESCRIPTION = "Nagios Plugin to check that an Ambari managed Hadoop cluster has Kerberos security enabled via Ambari REST API

Returns CRITICAL if security_type != KERBEROS

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

validate_tls();

vlog2;
set_timeout();

$status = "OK";

$url_prefix = "$protocol://$host:$port$api";

list_ambari_components();
cluster_required();

$msg = "Ambari cluster '$cluster' security type = ";
$json = curl_ambari "$url_prefix/clusters/$cluster?fields=Clusters/security_type";
my $security_type = get_field("Clusters.security_type");
$msg .= $security_type;
if($security_type ne "KERBEROS"){
    critical;
    $msg .= " (expected KERBEROS)";
}

vlog2;
quit $status, $msg;
