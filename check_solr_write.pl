#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-06-03 18:48:03 +0100 (Tue, 03 Jun 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin check Solr via API write and read back of a uniquely generated document

Configurable warning/critical thresholds apply to write/read/delete millisecond times for the unique test document. This is primarily to check write latency. If wanting to test query latency separately then the adjacent check_solr_query.pl plugin is a more targeted choice for that.

Performs a hard commit by default but if running Solr 4.x you may optionally specify to use a soft commit instead (will be ignored on Solr 3.x).

The default thresholds will need to be increased when testing SolrCloud on Hadoop HDFS as the write latency is massively higher, more than 10x in testing (700-1800ms on Hadoop vs 55-75ms on regular Solr / SolrCloud). Another possibility is to switch to using --soft-commits which brings write times down (warning threshold may still need to be increased)

Tested on Solr 3.1, 3.6.2 and Solr / SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1, 7.2, 7.3, 7.4, 7.5, 7.6";

# Originally designed for Solr 4.0 onwards due to using JSON and the standard update handler which only supports JSON from 4.0, later rewritten to support Solr 3 via XML document addition instead

$VERSION = "0.5.0";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(200, 2000);

my $soft_commit;
my $no_delete;
#my $sleep = 10;

%options = (
    %solroptions,
    %solroptions_collection,
    %solroptions_list_cores,
    %solroptions_context,
    %thresholdoptions,
    "soft-commit"   =>  [ \$soft_commit,    "Soft commit instead of hard commit" ],
    "d|no-delete"   =>  [ \$no_delete,      "Don't delete test inserted document (useful for debugging)" ],
    #"sleep=s"       =>  [ \$sleep,          "Sleep in milliseconds between writing unique document and querying to verify it (default: 10)" ],
);
splice @usage_order, 6, 0, qw/collection soft-commit no-delete sleep list-collections list-cores http-context/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
unless($list_collections or $list_cores){
    $collection = validate_solr_collection($collection);
    #validate_int($sleep, "sleep", 1, 2000);
    validate_thresholds();
}
$http_context = validate_solr_context($http_context);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

list_solr_collections();
list_solr_cores();

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
$json = curl_solr "$http_context/$collection/update?commit=true" . ( $soft_commit ? "&softCommit=true" : "") . "&overwrite=false", "POST", $xml_doc;

$msg .= "wrote unique document to Solr collection '$collection' in ${query_time}ms";
check_thresholds($query_time);
my $msg2 = "write_time=${query_time}ms" . msg_perf_thresholds(1) . " write_QTime=${query_qtime}ms";

#vlog2 "sleeping for $sleep ms to allow commit to complete before we query for document";
#sleep $sleep / 1000;

vlog2 "\nquerying for unique document";
# hacky workaround because Solr 5 breaks on this text/xml if there is no xml body :-(
my $default_header = $ua->default_headers();
delete $default_header->{'content-type'};
$ua->default_headers($default_header);
$json = query_solr($collection, "id:$unique_id");

# reuse specific error from get_field
defined($num_found) or get_field_int("response.numFound");
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
$msg2 .= " read_time=${query_time}ms" . msg_perf_thresholds(1) . " read_QTime=${query_qtime}ms";

unless($no_delete){
    my $xml_delete = "
    <delete>
        <id>$unique_id</id>
    </delete>
    ";
    vlog2 "\ndeleting unique document";
    $ua->default_header("Content-Type" => "application/xml");
    $json = curl_solr "$http_context/$collection/update", "POST", $xml_delete;

    ( $query_status eq 0 ) or quit "CRITICAL", "failed to delete unique document with id '$unique_id'";
    $msg .= ", deleted in ${query_time}ms";
    check_thresholds($query_time);
    $msg2 .= " delete_time=${query_time}ms" . msg_perf_thresholds(1) . " delete_QTime=${query_qtime}ms";
}

$msg .= " | $msg2";

vlog2;
quit $status, $msg;
