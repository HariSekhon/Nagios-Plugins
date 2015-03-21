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

hint: use -vvv to see the full debug output of what settings are returned by Elasticsearch

Caveats: since Elasticsearch doesn't output settings which have default values, there is no way to determine whether a given arbitrary key is in it's default setting or if the key is simply not a valid setting that will never show up.

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

my $expected_shards;
my $expected_replicas;
my $key;
my $expected_value;

%options = (
    %hostoptions,
    %elasticsearch_index,
    "A|shards=s"   =>  [ \$expected_shards,    "Expected shards (optional)" ],
    "R|replicas=s" =>  [ \$expected_replicas,  "Expected replicas (optional)" ],
    "K|key=s"      =>  [ \$key,                "Expected setting key to check (eg. index.refresh_interval), will be prefixed with 'index.' if not starting with index for convenience of being able to use shorter keys" ],
    "L|value=s"    =>  [ \$expected_value,     "Expected setting value (optional, eg. 30, use 'default' to check the key doesn't exist which implies default value)" ],
);
push(@usage_order, qw/shards replicas key value/);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$index = validate_elasticsearch_index($index);
$expected_shards   = validate_int($expected_shards,   "expected shards",   1, 1000000) if defined($expected_shards);
$expected_replicas = validate_int($expected_replicas, "expected replicas", 1, 1000)    if defined($expected_replicas);
if(defined($key)){
    #defined($expected_value) or usage "--expected-value must be defined if specifying --expected-key";
    $key =~ /^(\w[\w\.\*]+)$/ or usage "invalid --key";
    $key = "index.$key" unless $key =~ /^index\./;
    vlog_options "key", $key;
    vlog_options "expected value", $expected_value if defined($expected_value);
}
if(defined($expected_value)){
    defined($key) or usage "--key must be defined if specifying --expected-value";
}

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

curl_elasticsearch "/$index/_settings?flat_settings";

# escape any dots in index name to not separate
( my $index2 = $index ) =~ s/\./\\./g;

sub get_flat_setting($;$){
    my $setting = shift;
    my $not_required = shift;
    $setting =~ s/\./\\./g;
    $setting = "$index.settings.$setting";
    vlog2 "extracting setting key $setting\n";
    get_field($setting, $not_required);
}

# switched to flat settings, must escape dots inside the setting now
#my $shards   = get_field_int("$index2.settings.index.number_of_shards");
#my $replicas = get_field_int("$index2.settings.index.number_of_replicas");
my $shards   = get_field_int("$index2.settings.index\\.number_of_shards");
my $replicas = get_field_int("$index2.settings.index\\.number_of_replicas");

$msg = "index '$index'";
my $msg2 = "";

sub msg_shards_replicas(){
    $msg .= " shards=$shards";
    check_string($shards, $expected_shards) if defined($expected_shards);
    $msg .= " replicas=$replicas";
    check_string($replicas, $expected_replicas) if defined($expected_replicas);
    $msg2 .= " shards=$shards replicas=$replicas";
}

my $value;
if(defined($key)){
    if($expected_shards or $expected_replicas){
        msg_shards_replicas();
        $msg .= ",";
    }
    $value = get_flat_setting($key, 1);
    if(defined($value)){
        ( my $key2 = $key ) =~ s/^index\.//;
        $msg .= " setting $key2=$value";
        check_string($value, $expected_value) if defined($expected_value);
        if(isFloat($value)){
            $msg2 .= " '$key2'=$value";
        }
    } elsif(defined($expected_value) and $expected_value eq 'default'){
        $msg .= " setting $key=unset (default)";
    } else {
        critical;
        $msg .= " setting $key NOT FOUND";
        $msg .= " (expected '$expected_value')" if defined($expected_value);
    }
} else {
    msg_shards_replicas();
}

$msg .= " |$msg2" if $msg2;

quit $status, $msg;
