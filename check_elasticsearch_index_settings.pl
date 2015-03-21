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

$DESCRIPTION = "Nagios Plugin to check the settings of a given Elasticsearch index";

$VERSION = "0.1";

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
    %elasticsearch_index,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$index = validate_elasticsearch_index($index);

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

curl_elasticsearch "/$index/_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;
my $replicas = get_field_int("$index2.settings.index.number_of_replicas");
my $shards   = get_field_int("$index2.settings.index.number_of_shards");

$msg = "index '$index' shards=$shards replicas=$replicas | shards=$shards replicas=$replicas";

quit $status, $msg;
