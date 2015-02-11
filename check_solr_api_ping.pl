#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-07 18:29:01 +0100 (Sat, 07 Jun 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Solr availability via the in-built Solr API Ping

Must specify collection name if differing from the default 'collection1' since this API Ping is per collection and will result in a \"404 Not Found\" error if the collection doesn't exist on the Solr server

Configurable warning/critical thresholds apply to this API call's millisecond time, as reported by Solr (QTime). To check write QTime, see the adjacent program check_solr_write.pl

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.x";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;
use Math::Round;
use Time::HiRes 'time';

$ua->agent("Hari Sekhon $progname $main::VERSION");

set_threshold_defaults(200, 1000);

my $api_ping;

%options = (
    %solroptions,
    %solroptions_collection,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
unless(defined($collection)){
    $collection = "collection1";
}
$collection = validate_collection($collection);
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 });
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

$url = "solr/$collection/admin/ping?distrib=false";

$json = curl_solr $url;

my $qstatus = get_field("status");
unless($qstatus eq "OK"){
    critical;
}
$msg .= "Solr API ping returned '$qstatus' for collection '$collection'" . ( $verbose ? " (" . get_field("responseHeader.params.q") . ")" : "") . ", query time ${query_time}ms";
check_thresholds($query_time);
$msg .= " QTime ${query_qtime}ms | ";

$msg .= sprintf('query_time=%dms', $query_time);
msg_perf_thresholds();
$msg .= sprintf(' query_QTime=%dms', $query_qtime);

quit $status, $msg;
