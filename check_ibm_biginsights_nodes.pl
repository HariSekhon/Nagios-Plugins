#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_cluster_mgt.html?lang=en

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Nodes via the BigInsights Console REST API

Checks:

- dead nodes vs thresholds (default: w=0, c=1)
- outputs perfdata of live and dead nodes

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;

set_threshold_defaults(0, 1);

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %biginsights_options,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds();
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

curl_biginsights "/ClusterStatus/cluster_summary.json", $user, $password;

my $nodes;
isArray(get_field("items")) or quit "UNKNOWN", "'items' field is not an array as expected. $nagios_plugins_support_msg_api";
foreach my $item (@{$json->{"items"}}){
    if(get_field2($item, "id") eq "nodes"){
        $nodes = $item;
    }
}
$nodes or quit "UNKNOWN", "couldn't find 'nodes' item in json returned by BigInsights Console. $nagios_plugins_support_msg_api";
foreach(qw/live dead/){
    isInt(get_field2($nodes, $_))  or quit "UNKNOWN", "'$_' field was not an integer as expected (returned: " . $nodes->{$_} . ")! $nagios_plugins_support_msg_api";
}
$msg .= "BigInsights ";
foreach(qw/live dead/){
    $msg .= sprintf("%s nodes = %s, ", $_, $nodes->{$_});
}
$msg =~ s/, $//;
vlog2 "checking dead nodes against thresholds";
check_thresholds($nodes->{"dead"});
$msg .= sprintf(" | 'live nodes'=%d 'dead nodes'=%d", $nodes->{"live"}, $nodes->{"dead"});
msg_perf_thresholds();

vlog2;
quit $status, $msg;
