#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-03 18:48:03 +0100 (Tue, 03 Jun 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin check Solr via API write and read back of a uniquely generated document

Optional warning/critical thresholds may be applied to the query times which will apply to write, read and delete of the unique test document.

Test on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.x";

# Originally designed for Solr 4.0 onwards due to using JSON and the standard update handler which only supports JSON from 4.0, later rewritten to support Solr 3 via XML document addition instead

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Solr;
use Sys::Hostname 'hostname';
use Time::HiRes qw/sleep time/;
use XML::Simple;

$ua->agent("Hari Sekhon $progname $main::VERSION");

set_threshold_defaults(100, 2000);

%options = (
    %solroptions,
    %solroptions_collection,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/collection/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$collection = validate_solr_collection($collection) unless $list_collections;
validate_thresholds();
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();

my $hostname  = hostname;
my $epoch     = time;
my $unique_id = "$hostname,HariSekhon,$progname,$host,$port,$epoch," . random_alnum(20);

# xml document update will work with Solr 3.x as well as Solr 4.x
#my $json_doc = "
#'add': {
#    'doc': {
#        'id': '$unique_id',
#    }
#},
#";

my $xml_doc = "
<add>
    <doc>
      <field name='id'>$unique_id</field>
    </doc>
</add>
";

#$ua->default_header("Content-Type" => "application/json");
$ua->default_header("Content-Type" => "application/xml");

vlog2 "adding unique document to Solr collection '$collection'";
vlog3 "document id '$unique_id'";
$json = curl_solr "solr/$collection/update?commit=true&overwrite=false", "POST", $xml_doc;
$query_status eq 0 or quit "CRITICAL", "failed to write doc to Solr, got status '$query_status' (expected: 0)";

$msg .= "wrote unique document to Solr collection '$collection' in ${query_time}ms";
check_thresholds($query_time);
my $msg2 = "write_time=${query_time}ms" . msg_perf_thresholds(1);

sleep 0.1;

vlog2 "\nquerying for unique document";
$json = query_solr($collection, "id:$unique_id");

my $num_found = get_field_int("response.numFound");
unless($num_found == 1){
    quit "CRITICAL", "$num_found docs found matching unique generated id for document just written";
}
my @docs = get_field_array("response.docs");
foreach(@docs){
    ( get_field2($_, 'id') eq $unique_id ) or quit "CRITICAL", "returned document mismatch on unique id, expected '$unique_id', got '" . get_field2($_, 'id') . "'";
}
#$msg .= ", queried and confirmed match on exactly $num_found matching document in ${query_time}ms";
$msg .= ", retrieved in ${query_time}ms";
check_thresholds($query_time);
$msg2 .= " read_time=${query_time}ms" . msg_perf_thresholds(1);

my $xml_delete = "
<delete>
    <id>$unique_id</id>
</delete>
";
vlog2 "\ndeleting unique document";
$json = curl_solr "solr/$collection/update", "POST", $xml_delete;

( $query_status eq 0 ) or quit "CRITICAL", "failed to delete unique document with id '$unique_id'";
$msg .= ", deleted in ${query_time}ms";
check_thresholds($query_time);
$msg2 .= " delete_time=${query_time}ms" . msg_perf_thresholds(1);

$msg .= " | $msg2";

quit $status, $msg;
