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

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/cluster_info.html#storage-capacity

$DESCRIPTION = "Nagios Plugin to check Cassandra storage capacity % used via DataStax OpsCenter Rest API

Tested on DataStax OpsCenter 3.2.2 and 5.0.0";

$VERSION = "0.3.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(80, 90);

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100 });

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

$json = curl_opscenter "$cluster/storage-capacity";

my $free_gb         = get_field_float("free_gb");
my $used_gb         = get_field_float("used_gb");
my $reporting_nodes = get_field_int("reporting_nodes");

vlog2 "free_gb: $free_gb";
vlog2 "used_gb: $used_gb";

my $total_gb = $free_gb + $used_gb;
vlog2 "total_gb: $total_gb";

my $pc_used;
if($total_gb == 0 or $reporting_nodes == 0){
    quit "UNKNOWN", "total space = ${total_gb} GB across $reporting_nodes reporting nodes";
} else {
    $pc_used = sprintf("%.2f", $used_gb / $total_gb * 100);
}

$msg = sprintf("%s%% space used in cassandra cluster '%s' [%s/%s]", $pc_used, $cluster, human_units($used_gb * 1024 * 1024 * 1024), human_units($total_gb * 1024 * 1024 * 1024));
check_thresholds($pc_used);
$msg .= " across $reporting_nodes reporting nodes | '% space used'=$pc_used%";
msg_perf_thresholds();
$msg .= " 'space used'=${used_gb}GB 'space free'=${free_gb}GB 'space total'=${total_gb}GB 'reporting nodes'=$reporting_nodes";

vlog2;
quit $status, $msg;
