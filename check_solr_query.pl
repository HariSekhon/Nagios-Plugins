#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-03 18:48:14 +0100 (Tue, 03 Jun 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to query Solr and verify the number of documents return are within the expected range for the query

This uses the Solr /select SearchHandler so should be using Lucene query syntax.

The query may be case sensitive depending on your Solr analyzer configuration.

Configurable warning/critical thresholds apply to the query (read) millisecond time, as reported by Solr (QTime). To check write QTime, see the adjacent program check_solr_write.pl

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6";

$VERSION = "0.6.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(100, 2000);

my $query = "*:*";
my $filter;
my $num_docs_threshold = 1;

%options = (
    %solroptions,
    %solroptions_collection,
    %solroptions_list_cores,
    %solroptions_context,
    "q|query=s"    => [ \$query,              "Query to send to Solr (defaults to \"*:*\")" ],
    "f|filter=s"   => [ \$filter,             "Filter to send to Solr, use instead of query in order to make better use of caching (optional)" ],
    "n|num-docs=s" => [ \$num_docs_threshold, "Minimum or range threshold for number of matching docs to expect in result for given query (default: 1)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection query filter num-docs list-collections list-cores http-context/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
unless($list_collections or $list_cores){
    $collection = validate_solr_collection($collection);
    $query or usage "query not defined";
    vlog_option "query", $query;
    vlog_option "filter", $filter if defined($filter);
    validate_thresholds(0, 0, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1}, "num docs", $num_docs_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1});
}
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();
list_solr_cores();

$json = query_solr($collection, $query, $filter);

# reuse specific error from get_field
$num_found = get_field_int("response.numFound") unless defined($num_found);
#my @docs = get_field("responseHeader.response.docs");
# docs id, name fields etc

$msg = "$num_found matching documents found";
check_thresholds($num_found, 0, "num docs");
$msg .= ", query time ${query_time}ms";
check_thresholds($query_time);

$msg .= ", QTime ${query_qtime}ms | num_matching_docs=$num_found";
msg_perf_thresholds(0, "lower", "num docs");

$msg .= " query_time=${query_time}ms";
msg_perf_thresholds();
$msg .= " query_QTime=${query_qtime}ms";

quit $status, $msg;
