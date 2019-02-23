#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2016-10-05 19:56:50 +0100 (Wed, 05 Oct 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

# https://www.elastic.co/guide/en/elasticsearch/reference/current/cat-allocation.html

# forked from check_elasticsearch_node_stats.pl

$DESCRIPTION = "Nagios Plugin to check the number of pending tasks in an Elasticsearch cluster via the API

Tested on Elasticsearch 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults("0:20", 30);

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
validate_thresholds(1, 1, { 'simple' => 'upper', 'integer' => 1, 'positive' => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/_cluster/pending_tasks";
my $json = curl_elasticsearch $url;

my @pending_tasks = get_field_array("tasks");

my $num_pending_tasks = scalar @pending_tasks;

plural $num_pending_tasks;
$msg = "Elasticsearch has $num_pending_tasks pending task$plural";
check_thresholds($num_pending_tasks);
$msg .= " | num_pending_tasks=$num_pending_tasks";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
