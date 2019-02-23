#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-03-21 16:53:17 +0000 (Sat, 21 Mar 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check the number of docs in an Elasticsearch cluster or for a given index

Optional --warning/--critical threshold ranges may be applied to the number of docs

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.2.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %elasticsearch_index,
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$index = validate_elasticsearch_index($index) if $index;
validate_thresholds(0, 0);

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

my $url = "/_cat/count";
$url .= "/$index" if $index;
my $content = curl_elasticsearch_raw $url;

my @parts = split(/\s+/, $content);
defined($parts[2]) or quit "UNKNOWN", "failed to parse result. $nagios_plugins_support_msg_api";
isInt($parts[2]) or quit "UNKNOWN", "returned non-integer value for doc count. $nagios_plugins_support_msg_api";
my $docs = $parts[2];

$msg = "elasticsearch ";
if($index){
    $msg .= "index '$index'"
} else {
    $msg .= "cluster";
}
$msg .= " docs=$docs";
check_thresholds($docs);

$msg .= " | docs=$docs";
msg_perf_thresholds();

quit $status, $msg;
