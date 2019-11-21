#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-14 20:36:54 +0000 (Sat, 14 Feb 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of live SolrCloud servers via Solr Collections API

Thresholds for warning / critical apply to the minimum number of live nodes found

See also check_solrcloud_live_nodes_zookeeper.pl which does the same as this plugin but via ZooKeeper, which is more robust in case given Solr host is down.

Tested on SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1";

$VERSION = "0.3.0";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;

%options = (
    %solroptions,
    %solroptions_context,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/http-context/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
validate_ssl();
$http_context = validate_solr_context($http_context);
validate_thresholds(1, 1, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1});

$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

$json = curl_solr "$solr_admin/collections?action=CLUSTERSTATUS";

my @live_nodes = get_field_array("cluster.live_nodes");
my $live_nodes = scalar @live_nodes;

vlog2 "live nodes:\n\n" . join("\n", sort @live_nodes);
vlog2 "\ntotal live nodes: $live_nodes\n";

plural $live_nodes;
$msg = "$live_nodes live SolrCloud node$plural detected";
check_thresholds($live_nodes);
if($verbose){
    $msg .= " [";
    foreach(@live_nodes){
        s/_solr$//;
        $msg .= "$_, ";
    }
    $msg =~ s/, $//;
    $msg .= "]";
}

#$msg .= sprintf(", query_time=%dms, QTime=%dms", $query_time, $query_qtime) if $verbose;
$msg .= sprintf(" | live_nodes=%d", $live_nodes);
msg_perf_thresholds(0, "lower");
$msg .= sprintf(" query_time=%dms query_QTime=%dms", $query_time, $query_qtime);

vlog2;
quit $status, $msg;
