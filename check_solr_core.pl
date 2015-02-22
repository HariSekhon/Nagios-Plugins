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

$DESCRIPTION = "Nagios Plugin to check the stats of a Solr 4 core on the server instance for a given collection

Optional thresholds on the core's index size, heap size, number of documents and query time

Tested on Solr / SolrCloud 4.x";

our $VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $core_heap_threshold;
my $core_size_threshold;
my $core_num_docs_threshold;

%options = (
    %solroptions,
    %solroptions_collection,
    %solroptions_context,
    "s|index-size=s" => [ \$core_size_threshold,     "Core index size thresholds in MB" ],
    "e|heap-size=s"  => [ \$core_heap_threshold,     "Core heap size thresholds in MB" ],
    "n|num-docs=s"   => [ \$core_num_docs_threshold, "Core number of documents thresholds" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection index-size heap-size num-docs query-time list-collections http-context/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
unless($list_collections){
    $collection = validate_solr_collection($collection);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core heap",  $core_heap_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core size",  $core_size_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "num docs",   $core_num_docs_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 });
}
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

# This is disabled in newer versions of Solr
#} elsif($stats){
#    $url .= "/stats.jsp";

$json = curl_solr "$solr_admin/cores?distrib=false";

my $sizeInMB;
my $maxDoc;
my $numDocs;
my $deletedDocs;
my $segmentCount;
my $indexHeapUsageMB;

$msg .= "";
my %cores = get_field_hash("status");
my $name;
my $found = 0;
foreach(sort keys %cores){
    $name = get_field2($cores{$_}, "name");
    quit "UNKNOWN", "collection '$_' does not match name field '$name'" if ($name ne $_);
    next unless $name eq $collection;
    $found++;
    $msg .= "core for collection '$name' ";
    $sizeInMB     = sprintf("%.2f", get_field("status.$name.index.sizeInBytes") / (1024*1024));
    $maxDoc       = get_field_int("status.$name.index.maxDoc");
    $numDocs      = get_field_int("status.$name.index.numDocs");
    $deletedDocs  = get_field_int("status.$name.index.deletedDocs");
    $segmentCount = get_field_int("status.$name.index.segmentCount");
    $indexHeapUsageMB = sprintf("%.2f", get_field_int("status.$name.index.indexHeapUsageBytes") / (1024*1024));
    $msg .= "indexSize: ${sizeInMB}MB"; # get_field("status.$name.index.size"); # this could be in KB
    check_thresholds($sizeInMB, 0, "core size");
    $msg .= ", indexHeapUsage: ${indexHeapUsageMB}MB";
    check_thresholds($indexHeapUsageMB, 0, "core heap");
    $msg .= ", numDocs: $numDocs";
    check_thresholds($numDocs, 0, "num docs");
    $msg .= ", maxDoc: $maxDoc";
    $msg .= ", deletedDocs: $deletedDocs";
    $msg .= ", segmentCount: $segmentCount";
    $msg .= ", isDefaultCore: "  . ( get_field_int("status.$name.isDefaultCore") ? "true" : "false" );
    $msg .= ", uptime: "         . sec2human(get_field_int("status.$name.uptime") / 1000);
    $msg .= ", started: "        . get_field("status.$name.startTime");
    $msg .= ", last modified: "  . get_field("status.$name.index.lastModified");
    $msg .= ", query time ${query_time}ms";
    check_thresholds($query_time);
    $msg .= ", QTime: ${query_qtime}ms";
}
$found or quit "CRITICAL", "core for '$collection' not found, core not loaded or incorrect --collection name given. Use --list-collections to see available cores";
$msg .= " |";
$msg .= " indexSize=${sizeInMB}MB";
msg_perf_thresholds(0, 0, 'core size');
$msg .= " indexHeapUsage=${indexHeapUsageMB}MB";
msg_perf_thresholds(0, 0, 'core heap');
$msg .= " numDocs=$numDocs";
msg_perf_thresholds(0, 0, 'num docs');
$msg .= " maxDoc=$maxDoc";
$msg .= " segmentCount=$segmentCount";
$msg .= " ";

$msg .= sprintf('query_time=%dms', $query_time);
msg_perf_thresholds();
$msg .= sprintf(' query_QTime=%dms', $query_qtime);

vlog2;
quit $status, $msg;
