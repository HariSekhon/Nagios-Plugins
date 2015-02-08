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

# Todo checks:
#
# Number of queries / queries per second
# Average response time
# Number of updates
# Cache hit ratios
# Replication status
# Synthetic queries

$DESCRIPTION = "Nagios Plugin to check a Solr core for a given collection - heap, size, number of documents and query time

Tested on Solr / SolrCloud 4.x";

our $VERSION = "0.1";

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
my $query_time_threshold;

%options = (
    %solroptions,
    %solroptions_collection,
    "core-heap=s"       => [ \$core_heap_threshold,     "Core heap size thresholds in MB" ],
    "core-size=s"       => [ \$core_size_threshold,     "Core size thresholds in MB" ],
    "core-num-docs=s"   => [ \$core_num_docs_threshold, "Core num docs thresholds" ],
    "query-time=s"      => [ \$query_time_threshold,    "Query time thresholds in milliseconds (optional for both API ping and collection check)" ],
);
splice @usage_order, 4, 0, qw/collection core-heap core-size core-num-docs query-time list-collections/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$collection = validate_solr_collection($collection) unless $list_collections;
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core heap",  $core_heap_threshold);
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core size",  $core_size_threshold);
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "num docs",   $core_num_docs_threshold);
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "query time", $query_time_threshold);
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
    $msg .= "size: ${sizeInMB}MB"; # get_field("status.$name.index.size"); # this could be in KB
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
    $msg .= ", query time: ${query_time}ms";
    check_thresholds($query_time, 0, "query time");
}
$found or quit "CRITICAL", "core for '$collection' not found, core not loaded or incorrect --collection name given. Use --list-collections to see available cores";
$msg .= " |";
$msg .= " size=${sizeInMB}MB";
msg_perf_thresholds(0, 0, 'core size');
$msg .= " indexHeapUsage=${indexHeapUsageMB}MB";
msg_perf_thresholds(0, 0, 'core heap');
$msg .= " numDocs=$numDocs";
msg_perf_thresholds(0, 0, 'num docs');
$msg .= " maxDoc=$maxDoc";
$msg .= " segmentCount=$segmentCount";
$msg .= " ";

$msg .= sprintf('query_time=%dms', $query_time);
msg_perf_thresholds(0, 0, 'query time');

quit $status, $msg;
