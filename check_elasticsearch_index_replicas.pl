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

Tested on Elasticsearch 1.2.1 and 1.4.4";

$VERSION = "0.5";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected_replicas;

%options = (
    %hostoptions,
    %elasticsearch_index,
    "R|replicas=s" => [ \$expected_replicas, "Expected replicas (optional)" ],
);
push(@usage_order, qw/replicas/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$index = validate_elasticsearch_index($index);
$expected_replicas = validate_int($expected_replicas, "expected replicas", 1, 1000000) if defined($expected_replicas);

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

curl_elasticsearch "/$index/_settings?flat_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;

$msg = "index '$index'";

# switched to flat settings, must escape dots inside the setting now
#my $replicas   = get_field_int("$index2.settings.index.number_of_replicas");
my $replicas   = get_field_int("$index2.settings.index\\.number_of_replicas");
$msg .= " replicas=$replicas";
check_string($replicas, $expected_replicas) if defined($expected_replicas);
$msg .= " | replicas=$replicas";

quit $status, $msg;
