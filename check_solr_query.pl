#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-03 18:48:14 +0100 (Tue, 03 Jun 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to query Solr and verify the number of documents return are within the expected range for the query

This uses the Solr /select SearchHandler so should be using Lucene query syntax.

The query may be case sensitive depending on your Solr analyzer configuration.

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.x";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname $main::VERSION");

set_threshold_defaults(100, 2000);

my $query;
my $num_docs_threshold = 1;

%options = (
    %solroptions,
    %solroptions_collection,
    "q|query=s"    => [ \$query,              "Query to send to Solr" ],
    "n|num-docs=s" => [ \$num_docs_threshold, "Minimum or range threshold for number of matching docs to expect in result for given query (default: 1)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection query num-docs/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$collection = validate_solr_collection($collection) unless $list_collections;
$query or usage "query not defined";
validate_thresholds(0, 0, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1}, "num docs", $num_docs_threshold);
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1});
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

$json = query_solr($collection, $query);

my $num_found = get_field_int("response.numFound");
#my @docs = get_field("responseHeader.response.docs");
# docs id, name fields etc

$msg = "$num_found matching documents found";
check_thresholds($num_found, 0, "num docs");

$msg .= " | num_matching_docs=$num_found";
msg_perf_thresholds(0, undef, "num docs");

$msg .= " query_time=${query_time}ms";
msg_perf_thresholds();

quit $status, $msg;
