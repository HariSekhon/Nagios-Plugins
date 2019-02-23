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

$DESCRIPTION = "Nagios Plugin to check the number of replicas of a given Elasticsearch index

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.8.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

#my $expected_replicas = "1,0";
set_threshold_defaults(1,0);

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %elasticsearch_index,
    #"R|replicas=s" => [ \$expected_replicas, "Expected replicas (default: w,c = 1,0)" ],
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$index = validate_elasticsearch_index($index);
#$expected_replicas = validate_int($expected_replicas, "expected replicas", 0, 1000000) if defined($expected_replicas);
#validate_thresholds(0, 0, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1}, "expected replicas", $expected_replicas);
validate_thresholds(0, 0, { 'simple' => 'lower', 'positive' => 1, 'integer' => 1});

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

# breaks in Elasticsearch 5.0
#curl_elasticsearch "/$index/_settings?flat_settings&name=index.number_of_replicas";
curl_elasticsearch "/$index/_settings?flat_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;

$msg = "index '$index'";

# switched to flat settings, must escape dots inside the setting now
#my $replicas   = get_field_int("$index2.settings.index.number_of_replicas");
my $replicas   = get_field_int("$index2.settings.index\\.number_of_replicas");
$msg .= " replicas=$replicas";
#check_string($replicas, $expected_replicas) if defined($expected_replicas);
#check_thresholds($replicas, 0, "expected replicas");
check_thresholds($replicas);
$msg .= " | replicas=$replicas";
#msg_perf_thresholds(0, 'lower', 'expected replicas');
msg_perf_thresholds(0, 'lower');

quit $status, $msg;
