#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Elasticsearch cluster status with explanation of green / warning / red state in verbose mode

Optional check on cluster name is included.

Tested on Elasticsearch 0.90, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $cluster;

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    "C|cluster-name=s" => [ \$cluster, "Cluster name to expect (optional). Cluster name is used for auto-discovery and should be unique to each cluster in a single network" ],
);
splice @usage_order, 6, 0, qw/cluster-name/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$cluster = validate_elasticsearch_cluster($cluster) if defined($cluster);

vlog2;
set_timeout();

$status = "OK";

$json = curl_elasticsearch "/_cluster/health";

my $cluster_name = get_field("cluster_name");
$msg .= "cluster name: '$cluster_name'";
check_string($cluster_name, $cluster);

$msg .= check_elasticsearch_status(get_field("status"));

my $timed_out = get_field("timed_out");
#$timed_out = ( $timed_out ? "true" : "false" );
if($timed_out){
    critical;
    $msg .= ", TIMED OUT: TRUE";
    #check_string($timed_out, "false");
}

vlog2;
quit $status, $msg;
