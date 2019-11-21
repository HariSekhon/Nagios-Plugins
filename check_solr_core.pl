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

$DESCRIPTION = "Nagios Plugin to check the stats of a Solr 4 core on the server instance for a given core

Optional thresholds on the core's index size, heap size, number of documents and query time

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6";

our $VERSION = "0.4.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
use HariSekhon::Solr;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $core_heap_threshold;
my $core_size_threshold;
my $core_num_docs_threshold;

%options = (
    %solroptions,
    %solroptions_core,
    %solroptions_context,
    "s|index-size=s" => [ \$core_size_threshold,     "Core index size thresholds in MB (Solr 4.x)" ],
    "e|heap-size=s"  => [ \$core_heap_threshold,     "Core heap size thresholds in MB (Solr 4.x)" ],
    "n|num-docs=s"   => [ \$core_num_docs_threshold, "Core number of documents thresholds" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/core index-size heap-size num-docs query-time list-cores http-context/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
unless($list_cores){
    $core = validate_solr_core($core);
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

list_solr_cores();

# This is disabled in newer versions of Solr
#} elsif($stats){
#    $url .= "/stats.jsp";

# adding action=STATUS gives same output result
$json = curl_solr "$solr_admin/cores?distrib=false&core=$core";

my $sizeInMB;
my $sizeInBytes;
my $maxDoc;
my $numDocs;
my $deletedDocs;
my $segmentCount;
my $indexHeapUsageMB;
my $indexHeapUsageBytes;
my $isDefaultCore;

$msg .= "";
my %cores = get_field_hash("status");
my $name;
my $found = 0;
my $core_not_found_msg = "core for '$core' not found, core not loaded or incorrect --core name given. Use --list-cores to see available cores";
my $core2 = $core;
$core2 =~ s/\./\\./g;
foreach(sort keys %cores){
    if(isHash($cores{$_}) and not %{$cores{$_}}){
        # blank collection hash is returned when specifying a core that isn't found
        quit "CRITICAL", $core_not_found_msg;
    }
    $name = get_field2($cores{$_}, "name");
    # this seems to happen on Solr 3.x
    #quit "UNKNOWN", "core '$_' does not match name field '$name'" if ($name ne $_);
    #next unless $name eq $core;
    $found++;
    $msg .= "Solr core '$core' ";
    $sizeInBytes  = get_field("status.$core2.index.sizeInBytes", "noquit"); # not available in Solr 3.x
    $sizeInMB     = sprintf("%.2f", $sizeInBytes / (1024*1024)) if defined($sizeInBytes);
    $maxDoc       = get_field_int("status.$core2.index.maxDoc");
    $numDocs      = get_field_int("status.$core2.index.numDocs");
    $deletedDocs  = get_field_int("status.$core2.index.deletedDocs",  "noquit"); # not available in Solr 3.x
    $segmentCount = get_field_int("status.$core2.index.segmentCount", "noquit"); # not available in Solr 3.x
    # get_field("status.$core2.index.size"); # this could be in KB
    $indexHeapUsageBytes = get_field_int("status.$core2.index.indexHeapUsageBytes", "noquit"); # not available in Solr 3.x,
    $indexHeapUsageMB = sprintf("%.2f", $indexHeapUsageBytes / (1024*1024)) if defined($indexHeapUsageBytes);
    if(defined($sizeInMB)){
        $msg .= "indexSize: ${sizeInMB}MB";
        check_thresholds($sizeInMB, 0, "core size");
        $msg .= ", ";
    }
    if(defined($indexHeapUsageMB)){
        $msg .= "indexHeapUsage: ${indexHeapUsageMB}MB";
        check_thresholds($indexHeapUsageMB, 0, "core heap");
        $msg .= ", ";
    }
    $msg .= "numDocs: $numDocs";
    check_thresholds($numDocs, 0, "num docs");
    $msg .= ", maxDoc: $maxDoc";
    $msg .= ", deletedDocs: $deletedDocs" if defined($deletedDocs);
    $msg .= ", segmentCount: $segmentCount" if defined($segmentCount);
    $isDefaultCore = get_field_int("status.$core2.isDefaultCore", "noquit"); # not available in Solr 3.x
    $msg .= ", isDefaultCore: "  . ( $isDefaultCore ? "true" : "false" ) if defined($isDefaultCore);
    $msg .= ", uptime: "         . sec2human(get_field_int("status.$core2.uptime") / 1000);
    $msg .= ", started: "        . get_field("status.$core2.startTime");
    my $last_modified = get_field("status.$core2.index.lastModified", 1);
    $last_modified = "N/A" unless defined($last_modified);
    $msg .= ", last modified: $last_modified";
    $msg .= ", query time ${query_time}ms";
    check_thresholds($query_time);
    $msg .= ", QTime: ${query_qtime}ms";
}
$found or quit "CRITICAL", $core_not_found_msg;
$msg .= " |";
if(defined($sizeInMB)){
    $msg .= " indexSize=${sizeInMB}MB";
    msg_perf_thresholds(0, 0, 'core size');
}
if(defined($indexHeapUsageMB)){
    $msg .= " indexHeapUsage=${indexHeapUsageMB}MB";
    msg_perf_thresholds(0, 0, 'core heap');
}
$msg .= " numDocs=$numDocs";
msg_perf_thresholds(0, 0, 'num docs');
$msg .= " maxDoc=$maxDoc";
$msg .= " deletedDocs=$deletedDocs" if defined($deletedDocs);
$msg .= " segmentCount=$segmentCount" if defined($segmentCount);
$msg .= " ";

$msg .= sprintf('query_time=%dms', $query_time);
msg_perf_thresholds();
$msg .= sprintf(' query_QTime=%dms', $query_qtime);

vlog2;
quit $status, $msg;
