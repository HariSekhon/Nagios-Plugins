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

# https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-stats.html

$DESCRIPTION = "Nagios Plugin to check the stats for a given Elasticsearch index or all indices if no specific index given

- Can fetch one or more given stats (fetches all stats for 'total' if none are given)
- Optional --warning/--critical threshold ranges may be applied if specifying only one stat
- Will output stats KB/MB/GB/PB values in brackets in verbose mode for size_in_bytes stats

use -vv to see a convenient list of stats one per line to select from.

Tested on Elasticsearch 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $keys;
my $expected_value;
# hardly shortens it by anything 2846 chars vs 2596 - simpler for users to not deal with this and always be able to copy paste the output keys to the --key option
#my $shorten;

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %elasticsearch_index,
    "K|key=s"   => [ \$keys,            "Stat Key(s) to fetch (eg. total.docs.count, total.docs.deleted). Multiple keys may be comma separated, will be prefixed with 'total.' if not already starting with 'primaries' or 'total'. Optional, all 'total' stats will be printed if no specific stat(s) requested, can specify just 'primaries' to fetch all primaries stats instead of totals" ],
    #"shorten"   => [ \$shorten,        "Shorten key names using sections: instead of duplicating the full stat key name prefixes for every stat" ],
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
#if($progname =~ /index/){
#    $index or usage "index not specified";
#}
$index = validate_elasticsearch_index($index) if $index;
my @keys;
@keys = split(/\s*,\s*/, $keys) if defined($keys);
@keys = uniq_array @keys if @keys;
my $num_keys = scalar @keys;
if(@keys){
    foreach my $key (@keys){
        $key =~ /^([A-Za-z0-9][\w\.]+[A-Za-z0-9])$/ or usage "invalid --key '$key', must be alphanumeric with optional underscores and dashes in the middle";
        $key =~ /^(?:primaries|total)/ or $key = "total.$key";
        vlog_option "key", $key;
    }
}
if(defined($warning) or defined($critical)){
    defined($keys) or usage "--key must be defined if specifying thresholds";
    $num_keys == 1 or usage "must specify exactly one stat to check if using thresholds";
    ( $keys[0] eq "primaries" or $keys[0] eq "total" ) and usage "cannot specify 'primaries' or 'total' sections with thresholds";
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 0, 'positive' => 0});

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

my $url = "";
$url .= "/$index" if $index;
$url .= "/_stats";
$json = curl_elasticsearch $url;

if($index){
    # escape any dots in index name to not separate
    ( my $index2 = $index ) =~ s/\./\\./g;
    $json = get_field("indices.$index2");
    $msg = "index '$index'";
} else {
    $json = get_field("_all");
    $msg = "all indices";
}

my $msg2 = "";

sub recurse_stats($$);

sub recurse_stats($$){
    my $key = shift;
    my $val = shift;
    if(isHash($val)){
        $key .= "." if $key;
        foreach(sort keys %{$val}){
            recurse_stats("$key$_", ${$val}{$_});
        }
    } elsif(isArray($val)){
        $key .= "." if $key;
        #foreach(@{$val}){
        #    recurse_stats("$key$_", $_);
        #}
        foreach(my $i=0; $i < scalar @{$val}; $i++){
            recurse_stats("$key$i", $$val[$i]);
        }
    } else {
        vlog2 "$key=$val";
        my $key2 = $key;
        #$key2  =~ s/.*?\.// if $shorten;
        $key2  =~ s/^(?:primaries|total)\.//;
        $msg  .= " $key2=$val";
        if(isFloat($val)){
            $msg2 .= " '$key'=$val";
        }
        if($verbose){
            if($key =~ /[\b_]bytes$/ and isFloat($val) and $val > 1024){ # KB or above
                $msg  .= " (" . human_units($val) . ")";
            }
        }
        $msg2 .= perf_suffix($key);
    }
}

sub get_primaries_stats(){
    $msg .= " primaries";
    my $sections = get_field("primaries");
    foreach(sort keys %$sections){
        #$msg .= " $_:" if $shorten;
        recurse_stats("primaries.$_", $$sections{$_});
        #$msg .= ", " if $shorten;
    }
}

sub get_total_stats(){
    $msg .= " total";
    my $sections = get_field("total");
    foreach(sort keys %$sections){
        #$msg .= " $_:" if $shorten;
        recurse_stats("total.$_", $$sections{$_});
        #$msg .= ", " if $shorten;
    }
    vlog2;
}

sub get_stat($){
    my $key = shift;
    my $value;
    $value = get_field_float($key);
    # don't truncate prefix, this way user can mix and match primaries and total stats
    #( my $key2 = $key ) =~ s/.*?\.//;
    $msg .= " $key=$value";
    check_thresholds($value) if $num_keys == 1;
    if(isFloat($value)){
        $msg2 .= " '$key'=$value";
        $msg2 .= perf_suffix($key);
        $msg2 .= msg_perf_thresholds(1) if $num_keys == 1;
    }
}

plural $num_keys;
$msg .= " stat$plural:";
if($num_keys == 1){
    if($keys[0] eq "total"){
        get_total_stats();
    } elsif($keys[0] eq "primaries"){
        get_primaries_stats();
    } else {
        get_stat($keys[0]);
    }
} elsif(@keys){
    foreach my $key (@keys){
        get_stat($key);
    }
} else {
    get_total_stats();
    #$msg =~ s/, $//;
}

$msg .= " |$msg2" if $msg2;

vlog2;
quit $status, $msg;
