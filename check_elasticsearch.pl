#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given Elasticsearch node

Checks:

- node is online and returning json with ok 200 status
- optionally check node is a member of the expected cluster
- optionally checks node's Elasticsearch / Lucene versions
- in verbose mode also prints out the generated Marvel node name

Tested on Elasticsearch 0.90, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.4.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $cluster;
my $es_version_regex;
my $lc_version_regex;

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    "C|cluster=s"       => [ \$cluster,           "Cluster to expect membership of (optional, available from 1.3" ],
    "es-version=s"      => [ \$es_version_regex,  "Elasticsearch version regex to expect (optional)" ],
    "lucene-version=s"  => [ \$lc_version_regex,  "Lucene version regex to expect (optional)" ],
);
splice @usage_order, 6, 0, qw/cluster es-version lucene-version/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$cluster = validate_elasticsearch_cluster($cluster) if $cluster;
$es_version_regex = validate_regex($es_version_regex, "elasticsearch version") if defined($es_version_regex);
$lc_version_regex = validate_regex($lc_version_regex, "lucene version") if defined($lc_version_regex);

vlog2;
set_timeout();

$status = "OK";

$json = curl_elasticsearch "/";

my $elasticsearch_status = get_field("status", "noquit");
if(defined($elasticsearch_status)){
    $msg .= "status: '$elasticsearch_status', ";
    check_string($elasticsearch_status, 200);
}
my $cluster_name = get_field("cluster_name", 1);
if($cluster_name){
    $msg .= "cluster: '$cluster_name', ";
    check_string($cluster_name, $cluster) if $cluster;
}
my $node_name = get_field("name", 1);
$msg .= "node name: '$node_name', " if($node_name and $verbose);

my $es_version = get_field2(get_field("version"), "number");
my $lc_version = get_field2(get_field("version"), "lucene_version");
isVersion($es_version) or quit "UNKNOWN", "invalid version returned for elasticsearch";
isVersion($lc_version) or quit "UNKNOWN", "invalid version returned for lucene";
$msg .= "elasticsearch version: $es_version";
check_regex($es_version, $es_version_regex) if $es_version_regex;
$msg .= ", lucene version: $lc_version";
check_regex($lc_version, $lc_version_regex) if $lc_version_regex;

vlog2;
quit $status, $msg;
