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

$DESCRIPTION = "Nagios Plugin to check the settings of a given Elasticsearch index

Optional Checks:

- number of shards
- number of replicas
- any arbitrary setting key (eg. index.refresh_interval) against a given expected value or 'default' (meaning unset, implying it's still the default value)

Caveats: since Elasticsearch doesn't output settings which have default values, there is no way to determine whether a given arbitrary key is in it's default setting or if the key is simply not a valid setting that will never show up.

Tested on Elasticsearch 1.2.1 and 1.4.4";

$VERSION = "0.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected_shards;
my $expected_replicas;
my $expected_key;
my $expected_value;

%options = (
    %hostoptions,
    %elasticsearch_index,
    "expected-shards=s"   =>  [ \$expected_shards,    "Expected shards (optional)" ],
    "expected-replicas=s" =>  [ \$expected_replicas,  "Expected replicas (optional)" ],
    "expected-key=s"      =>  [ \$expected_key,       "Expected setting key (eg. index.refresh_interval), will be prefixed with 'index.' if not containg it to use shorter keys" ],
    "expected-value=s"    =>  [ \$expected_value,     "Expected setting value (eg. 30, use 'default' to check the key doesn't exist which implies default value)" ],
);
push(@usage_order, qw/expected-shards expected-replicas expected-key expected-value/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$index = validate_elasticsearch_index($index);
$expected_shards   = validate_int($expected_shards,   "expected shards",   1, 1000000) if defined($expected_shards);
$expected_replicas = validate_int($expected_replicas, "expected replicas", 1, 1000)    if defined($expected_replicas);
if(defined($expected_key)){
    defined($expected_value) or usage "--expected-value must be defined if specifying --expected-key";
    $expected_key =~ /^(\w[\w\.\*]+)$/ or usage "invalid --expected-key";
    $expected_key = "index.$expected_key" unless $expected_key =~ /^index\./;
}
if(defined($expected_value)){
    defined($expected_key) or usage "--expected-key must be defined if specifying --expected-value";
}

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

curl_elasticsearch "/$index/_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;
my $replicas = get_field_int("$index2.settings.index.number_of_replicas");
my $shards   = get_field_int("$index2.settings.index.number_of_shards");

sub msg_shards_replicas(){
    $msg .= " shards=$shards";
    check_string($shards, $expected_shards) if defined($expected_shards);
    $msg .= " replicas=$replicas";
    check_string($replicas, $expected_replicas) if defined($expected_replicas);
}

$msg = "index '$index'";

my $value;
if(defined($expected_key)){
    if($expected_shards or $expected_replicas){
        msg_shards_replicas();
        $msg .= ",";
    }
    #( my $key = $expected_key ) =~ s/\./\\./g;
    vlog2 "extracting setting key $index2.settings.$expected_key";
    $value = get_field("$index2.settings.$expected_key", 1);
    if(defined($value)){
        $msg .= " setting $expected_key=$value";
        check_string($value, $expected_value) if defined($expected_value);
    } elsif($expected_value eq 'default'){
        $msg .= " setting $expected_key=unset (default)";
    } else {
        critical;
        $msg .= " setting $expected_key not found (expected $expected_value)";
    }
} else {
    msg_shards_replicas();
}

$msg .= " | shards=$shards replicas=$replicas";

quit $status, $msg;
