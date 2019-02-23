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

$DESCRIPTION = "Nagios Plugin to check a given Elasticsearch index exists and optionally wasn't (re)created less than N days ago. Also prints the index's UUID

Tested on Elasticsearch 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.7.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
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
$index = validate_elasticsearch_index($index);
validate_thresholds(0, 0, {'simple' => 'lower', 'positive' => 1, 'integer' =>1} );

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

#curl_elasticsearch "/$index/_settings?flat_settings&name=index.number_of_days";
# breaks in Elasticsearch 5.0
#curl_elasticsearch "/$index/_settings?flat_settings&index.uuid&index.creation_date"; # still pulls all index settings
curl_elasticsearch "/$index/_settings?flat_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;

$msg = "index '$index' age = ";

# switched to flat settings, must escape dots inside the setting now
my $epoch_millis = get_field_int("$index2.settings.index\\.creation_date");
my $epoch = int($epoch_millis / 1000.0);
my $age_secs =  time - $epoch;
my $days = int($age_secs / 86400);
$msg .= sec2human($age_secs);
check_thresholds($days);
$msg .= ", uuid = " . get_field("$index2.settings.index\\.uuid");
$msg .= ", version created = " . get_field_int("$index2.settings.index\\.version\\.created");

vlog2;
quit $status, $msg;
