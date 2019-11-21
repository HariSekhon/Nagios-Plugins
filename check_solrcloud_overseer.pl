#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-07 18:29:01 +0100 (Sat, 07 Jun 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Solr / SolrCloud Overseer via SolrCloud Collections API

Thresholds apply to the query time.

See also adjacent plugin check_solrcloud_overseer_zookeeper.pl which does the same but via ZooKeeper

Tested on SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1";

our $VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

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
validate_thresholds();
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

$json = curl_solr "$http_context/admin/collections?action=OVERSEERSTATUS&distrib=true";

my $overseer = get_field("leader");

$msg .= "SolrCloud overseer leader is '$overseer', query time ${query_qtime}ms";
check_thresholds($query_time);
$msg .= ", QTime ${query_qtime}ms";
$msg .= sprintf(' | query_time=%dms', $query_time);
msg_perf_thresholds();
$msg .= sprintf(' query_QTime=%sms', $query_time, $query_qtime);

vlog2;
quit $status, $msg;
