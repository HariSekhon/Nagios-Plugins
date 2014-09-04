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

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/cluster_info.html#storage-capacity

$DESCRIPTION = "Nagios Plugin to check Cassandra storage capacity % used via DataStax OpsCenter Rest API

Tested on DataStax OpsCenter 5.0.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8888);
set_threshold_defaults(80, 90);

env_creds("DataStax OpsCenter");

my $cluster;
my $list_clusters;

%options = (
    %hostoptions,
    %useroptions,
    "C|cluster=s"   =>  [ \$cluster, "Cluster as named in DataStax OpsCenter. See --list-clusters" ],
    "list-clusters" =>  [ \$list_clusters, "List clusters managed by DataStax OpsCenter" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/cluster list-clusters/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
unless($list_clusters){
    $cluster or usage "must specify cluster, use --list-clusters to show clusters managed by DataStax OpsCenter";
    $cluster =~ /^[A-Za-z0-9]+$/ or usage "invalid cluster name given, must be alphanumeric";
}
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100 });

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $url;
if($list_clusters){
    $url = "http://$host:$port/cluster-configs";
} else {
    $url = "http://$host:$port/$cluster/storage-capacity";
}

my $content = curl $url, "DataStax OpsCenter", $user, $password;
try{
    $json = isJson($content);
};
catch {
    quit "CRITICAL", "invalid json returned by DataStax OpsCenter at $url";
};

if($list_clusters){
    print "Clusters managed by DataStax OpsCenter:\n\n";
    foreach(sort keys %{$json}){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $free_gb         = get_field_int("free_gb");
my $used_gb         = get_field_int("used_gb");
my $reporting_nodes = get_field_int("reporting_nodes");

vlog2 "free_gb: $free_gb";
vlog2 "used_gb: $used_gb";

my $total_gb = $free_gb + $used_gb;
vlog2 "total_gb: $total_gb";

my $pc_used = sprintf("%.2f", $used_gb / $total_gb * 100);

$msg = "$pc_used% space used in cassandra cluster '$cluster' [" . human_units($used_gb * 1024 * 1024 * 1024) . "/" . human_units($total_gb * 1024 * 1024 * 1024) . "]";
check_thresholds($pc_used);
$msg .= " across $reporting_nodes reporting nodes | '% space used'=$pc_used%";
msg_perf_thresholds();
$msg .= " 'space used'=${used_gb}GB 'space free'=${free_gb}GB 'space total'=${total_gb}GB 'reporting nodes'=$reporting_nodes";

vlog2;
quit $status, $msg;
