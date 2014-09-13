#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/data_modeling.html#method-get-keyspaces

$DESCRIPTION = "Nagios Plugin to check DataStax OpsCenter alerts for a given cluster via the DataStax OpsCenter Rest API

Requires the DataStax Enterprise

Tested on DataStax OpsCenter 5.0.0 with DataStax Enterprise Server 4.5.1";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8888);

env_creds("DataStax OpsCenter");

my $cluster;
my $list_clusters;

env_vars(["DATASTAX_OPSCENTER_CLUSTER", "CLUSTER"], \$cluster);

%options = (
    %hostoptions,
    %useroptions,
    "C|cluster=s"    =>  [ \$cluster,       "Cluster as named in DataStax OpsCenter (\$DATASTAX_OPSCENTER_CLUSTER, \$CLUSTER). See --list-clusters" ],
    "list-clusters" =>  [ \$list_clusters,  "List clusters managed by DataStax OpsCenter" ],
);
splice @usage_order, 6, 0, qw/cluster list-clusters/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
unless($list_clusters){
    $cluster or usage "must specify cluster, use --list-clusters to show clusters managed by DataStax OpsCenter";
    $cluster = validate_alnum($cluster, "cluster name");
}

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $url;
if($list_clusters){
    $url = "http://$host:$port/cluster-configs";
} else {
    $url = "http://$host:$port/$cluster/alerts/fired";
}

$json = curl_json $url, "DataStax OpsCenter", $user, $password;
vlog3 Dumper($json);

if($list_clusters){
    print "Clusters managed by DataStax OpsCenter:\n\n";
    foreach(sort keys %{$json}){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

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
