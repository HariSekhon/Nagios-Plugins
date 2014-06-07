#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013) 
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check basic ElasticSearch status and optionally ElasticSearch / Lucene versions";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ElasticSearch;
use LWP::Simple '$ua';

my $es_version_regex;
my $lc_version_regex;

%options = (
    %hostoptions,
    "elasticsearch-version=s"   => [ \$es_version_regex,  "ElasticSearch version regex to expect (optional)" ],
    "lucene-version=s"          => [ \$lc_version_regex,  "Lucene version regex to expect (optional)" ],
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
$es_version_regex = validate_regex($es_version_regex, "elasticsearch version") if defined($es_version_regex);
$lc_version_regex = validate_regex($lc_version_regex, "lucene version") if defined($lc_version_regex);

vlog2;
set_timeout();

$status = "OK";

$json = curl_elasticsearch "/";

my $elasticsearch_status = get_field("status");
$msg .= "status: '$elasticsearch_status'";
check_string($elasticsearch_status, 200);

my $es_version = get_field2(get_field("version"), "number");
my $lc_version = get_field2(get_field("version"), "lucene_version");
isVersion($es_version) or quit "UNKNOWN", "invalid version returned for elasticsearch";
isVersion($lc_version) or quit "UNKNOWN", "invalid version returned for lucene";
$msg .= ", elasticsearch version: $es_version";
check_regex($es_version, $es_version_regex);
$msg .= ", lucene version: $lc_version";
check_regex($lc_version, $lc_version_regex);

quit $status, $msg;
