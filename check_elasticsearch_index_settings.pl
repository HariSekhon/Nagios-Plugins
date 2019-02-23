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

Checks any arbitrary setting key (eg. index.refresh_interval) against a given expected value or 'default' (meaning unset, implying it's still the default value)

Caveats: since Elasticsearch doesn't output settings which have default values, there is no way to determine whether a given arbitrary key is in it's default setting or if the key is simply not a valid setting that will never show up.

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.7.0";

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
    %useroptions,
    %ssloptions,
    %elasticsearch_index,
    #"A|shards=s"   =>  [ \$expected_shards,    "Expected shards (optional)" ],
    #"R|replicas=s" =>  [ \$expected_replicas,  "Expected replicas (optional)" ],
    #"K|key=s"      =>  [ \$key,                "Setting key to check (eg. index.refresh_interval), will be prefixed with 'index.' if not starting with index for convenience of being able to use shorter keys" ],
    "K|key=s"      =>  [ \$key,                "Setting key to check (eg. index.refresh_interval)" ],
    "L|value=s"    =>  [ \$expected_value,     "Expected setting value (optional, eg. 30, use 'default' to check the key doesn't exist which implies default value)" ],
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$index = validate_elasticsearch_index($index);
#$expected_shards   = validate_int($expected_shards,   "expected shards",   1, 1000000) if defined($expected_shards);
#$expected_replicas = validate_int($expected_replicas, "expected replicas", 1, 1000)    if defined($expected_replicas);
if(defined($key)){
    #defined($expected_value) or usage "--expected-value must be defined if specifying --expected-key";
    $key =~ /^(\w[\w\.\*]+)$/ or usage "invalid --key";
    #$key = "index.$key" unless $key =~ /^index\./;
    vlog_option "key", $key;
    vlog_option "expected value", $expected_value if defined($expected_value);
}
if(defined($expected_value)){
    defined($key) or usage "--key must be defined if specifying --value";
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

$msg = "index '$index' setting";
my $msg2 = "";

#sub msg_shards(){
#    # switched to flat settings, must escape dots inside the setting now
#    #my $shards   = get_field_int("$index2.settings.index.number_of_shards");
#    my $shards   = get_field_int("$index2.settings.index\\.number_of_shards");
#    $msg .= " shards=$shards";
#    check_string($shards, $expected_shards) if defined($expected_shards);
#    $msg2 .= " shards=$shards";
#}
#
#sub msg_replicas(){
#    #my $replicas = get_field_int("$index2.settings.index.number_of_replicas");
#    my $replicas = get_field_int("$index2.settings.index\\.number_of_replicas");
#    $msg .= " replicas=$replicas";
#    check_string($replicas, $expected_replicas) if defined($expected_replicas);
#    $msg2 .= " replicas=$replicas";
#}

my $value;
if(defined($key)){
    #if(defined($expected_shards) or defined($expected_replicas)){
    #    msg_shards() if defined($expected_shards);
    #    msg_replicas() if defined($expected_replicas);
    #    $msg .= ",";
    #}
    $value = get_flat_setting($key, 1);
    if(defined($value)){
        ( my $key2 = $key ); # =~ s/^index\.//;
        $msg .= " $key2=$value";
        check_string($value, $expected_value) if defined($expected_value);
        if(isFloat($value)){
            $msg2 .= " '$key2'=$value";
        }
    } elsif(defined($expected_value) and $expected_value eq 'default'){
        $msg .= " $key=unset (default)";
    } else {
        critical;
        $msg .= " $key NOT FOUND";
        $msg .= " (expected '$expected_value')" if defined($expected_value);
    }
} else {
    $msg .= "s:";
    my %settings = get_field_hash("$index2.settings");
    foreach(sort keys %settings){
        ( my $key2 = $_ ); # =~ s/^index\.//;
        $value = $settings{$_};
        $msg .= " $_=$value";
        next if $key2 =~ /^(?:index.creation_date|index.version.created)$/;
        if(isFloat($value)){
            $msg2 .= " '$key2'=$value";
        }
    }
    #msg_shards();
    #msg_replicas();
}

$msg .= " |$msg2" if $msg2;

quit $status, $msg;
