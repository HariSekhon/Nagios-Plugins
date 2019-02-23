#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the state of Elasticsearch shards not in started state, especially for unassigned shards

Tested on Elasticsearch 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.4.0";

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
    %multilineoption,
);
$options{"I|index=s"}[1] .= ", defaults to showing all indices if unspecified";
splice @usage_order, 6, 0, qw/index/;

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$index = validate_elasticsearch_index($index) if defined($index);

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_indices();

# This only returns STARTED shards, defeating the purpose
#my $url = "";
#$url .= "/$index" if $index;
#$url .= "/_search_shards";
#
#$json = curl_elasticsearch $url;
#
#my @shards = get_field_array("shards");

my $content = curl_elasticsearch_raw "/_cat/shards";

my %shards;
my ($index2, $shard, $prirep, $state, $docs, $store, $ip, $node);
#my $primary;

#foreach(@shards){
#    foreach(@{$_}){
#        $index   = get_field2($_, "index");
#        $shard   = get_field2($_, "shard");
#        $state   = get_field2($_, "state");
#        $primary = get_field2($_, "primary");
#        $shards{$state}{$index}{$shard} = 1;
#    }
#}

foreach(split("\n", $content)){
    ($index2, $shard, $prirep, $state, $docs, $store, $ip, $node) = split(/\s+/, $_);
    next if($index and $index ne $index2);
    quit "UNKNOWN", "unknown shard type '$prirep' for index '$index2'. $nagios_plugins_support_msg_api" if $prirep ne "p" and $prirep ne "r";
    $shards{$state}{$index2}{$prirep}{$shard} = 1;
}

%shards or quit "UNKNOWN", "no shards found for index '$index'. Did you specify the correct index name? See --list-indices";

my $sep = ",";
$sep = "\n" if ($multiline and not $index);

my @states = keys %shards;
if(grep { "STARTED" ne $_ } @states){
    foreach(@states){
        if($_ eq "STARTING" or $_ eq "INITIALIZING"){
            warning;
        } else {
            critical;
        }
    }
    $msg = "shards not in started state: ";
    foreach my $state (sort keys %shards){
        next if $state eq "STARTED";
        if($multiline and not $index){
            $msg .= "$state:\nindex";
        } else {
            $msg .= "$state - index";
        }
        foreach $index (sort keys %{$shards{$state}}){
            $msg .= " '$index' ";
            foreach $prirep (sort keys %{$shards{$state}{$index}}){
                if($prirep eq "p"){
                    $msg .= "primary ";
                } elsif($prirep eq "r"){
                    $msg .= "replica ";
                } else {
                    code_error "unknown shard type '$prirep' for index '$index', caught late. $nagios_plugins_support_msg_api";
                }
                plural keys %{$shards{$state}{$index}{$prirep}};
                $msg .= "shard$plural\[" . join(",", sort { $a <=> $b } keys %{$shards{$state}{$index}{$prirep}}) . "]$sep";
            }
        }
        $msg .= " ";
    }
    $msg =~ s/, $//;
} else {
    $msg = "all shards in started state";
}

vlog2;
quit $status, $msg;
