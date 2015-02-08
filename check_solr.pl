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

$DESCRIPTION = "Nagios Plugin to check Solr / SolrCloud API accessibility or Solr core / collection details

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

my $api_ping;
my $core_name;
my $list_cores;
my $query_time_threshold;
my $core_heap_threshold;
my $core_size_threshold;
my $num_docs_threshold;

%options = (
    %hostoptions,
    #%useroptions,
    #%ssloptions,
    "api-ping"          => [ \$api_ping,             "Solr API Ping check" ],
    "core-name=s"       => [ \$core_name,            "Check a given Solr core/collection status and stats, thresholds below are optional" ],
    "core-heap=s"       => [ \$core_heap_threshold,  "Core heap size thresholds in MB" ],
    "core-size=s"       => [ \$core_size_threshold,  "Core size thresholds in MB" ],
    "core-num-docs=s"   => [ \$num_docs_threshold,   "Core num docs thresholds" ],
    "query-time=s"      => [ \$query_time_threshold, "Query time thresholds in milliseconds (optional for both API ping and core-name check)" ],
    "list-cores"        => [ \$list_cores,           "List Solr Cores and exit" ],
);
splice @usage_order, 4, 0, qw/api-ping core-name core-heap core-size core-num-docs query-time list-cores/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
#$user       = validate_user($user);
#$password   = validate_password($password) if $password;
#validate_ssl();
if(defined($core_name)){
    usage "cannot specify both --api-ping and a specific --core" if $api_ping;
    $core_name = validate_solr_collection($core_name);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core heap", $core_heap_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 0 }, "core size", $core_size_threshold);
    validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "num docs",  $num_docs_threshold);
} else {
    usage "cannot specify core thresholds without specifying --core-name" if ( defined($core_heap_threshold) or defined($core_size_threshold) or defined($num_docs_threshold) );
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'positive' => 1, 'integer' => 1 }, "query time", $query_time_threshold);

vlog2;
set_timeout();

$status = "OK";

$url = "$solr_admin/";

if($api_ping){
    $url .= "ping?distrib=false";
} elsif($core_name or $list_cores){
    $url .= "cores?distrib=true";
# This is disabled in newer versions of Solr
#} elsif($stats){
} else {
#    $url .= "stats.jsp";
    usage "select either --api-ping or --core-name to check";
}

$json = curl_solr $url;

if($list_cores){
    my %cores = get_field_hash("status");
    print "Solr Cores:\n\n";
    foreach(sort keys %cores){
        print get_field2($cores{$_}, "name") . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $sizeInMB;
my $maxDoc;
my $numDocs;
my $deletedDocs;
my $segmentCount;
my $indexHeapUsageMB;
if($api_ping){
    my $qstatus = get_field("status");
    unless($qstatus eq "OK"){
        critical;
    }
    $msg .= "Solr API ping " . ( $verbose ? "(" . get_field("responseHeader.params.q") . ") " : "") . "returned $qstatus, query time ${query_time}ms";
    check_thresholds($query_time, 0, "query time");
    $msg .= " | ";
} elsif($core_name){
    $msg .= "";
    my %cores = get_field_hash("status");
    my $name;
    my $found = 0;
    foreach(sort keys %cores){
        $name = get_field2($cores{$_}, "name");
        quit "UNKNOWN", "core '$_' does not match name field '$name'" if ($name ne $_);
        next unless $name eq $core_name;
        $found++;
        $msg .= "'$name' ";
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
    }
    $found or quit "CRITICAL", "core '$core_name' not found, core not loaded or incorrect --core-name given. Use --list-cores to see available cores";
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
} else {
    code_error "neither --api-ping nor --core specified and caught late. $nagios_plugins_support_msg";
}

$msg .= sprintf('query_time=%dms', $query_time);
msg_perf_thresholds(0, 0, 'query time');

quit $status, $msg;
