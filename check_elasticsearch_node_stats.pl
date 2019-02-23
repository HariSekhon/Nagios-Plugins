#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

# http://www.elastic.co/guide/en/elasticsearch/reference/current/cluster-nodes-stats.html

$DESCRIPTION = "Nagios Plugin to check the stats for a given Elasticsearch node

- Can fetch one or more given stats (fetches all stats if no specific ones are specified)
- Optional --warning/--critical threshold ranges if given are applied to the first float value found (--key order is preserved for this reason if wnating to return more than one thing at a time but still have a threshold on one of them, the first one in the --key list)
- Will output stats KB/MB/GB/PB values in brackets in verbose mode for size_in_bytes stats

Should specify an Elasticsearch node name rather than a hostname/FQDN/IP (see --list-nodes), as sometimes hosts may have more than once instance or client nodes like logstash-<fqdn>-<\\d+>-<\\d+> which also share the same hostname/FQDN and will result in multiple ambiguous matches, resulting in an UNKNOWN error condition to flag for user to correct this and be more specific.

For a convenient list of all stats one per line use -vv

Tested on Elasticsearch 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.2.0";

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

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    %elasticsearch_node,
    "K|key=s" => [ \$keys, "Stat Key(s) to fetch (eg. indices.docs.count, http.current_open, fs.total.available_in_bytes). Multiple keys may be comma separated. Optional, all stats will be printed if no specific stat(s) requested" ],
    %thresholdoptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
# this is the node name, not using validate_host because an IP returns logstash clients and don't want to have to deal with that
#$node  = validate_hostname($node, "node") unless $list_nodes;
# hostname is too restrictive because of default Marvel names, and in some cases we may want to just do it by IP or hostname or whatever as long as there are not more than one colocated node (including client nodes like LogStash) on the same hosts
unless($list_nodes){
    defined($node) or usage "node not defined, see --list-nodes";
    $node =~ /^([\w\s\._-]+)$/ or usage "invalid node name specified, must be alphanumeric, may contain spaces, dashes, underscores and dots";
    $node = $1;
}
my @keys;
@keys = split(/\s*,\s*/, $keys) if defined($keys);
@keys = uniq_array_ordered @keys if @keys;
my $num_keys = scalar @keys;
if(@keys){
    foreach my $key (@keys){
        $key =~ /^([A-Za-z0-9][\w\.]+[A-Za-z0-9])$/ or usage "invalid --key '$key', must be alphanumeric with optional underscores and dashes in the middle";
        vlog_option "key", $key;
    }
}
if(defined($warning) or defined($critical)){
    defined($keys) or usage "--key must be defined if specifying thresholds";
    # not true any more, applying to first stat
    #$num_keys == 1 or usage "must specify exactly one stat to check if using thresholds";
}
validate_thresholds(0, 0, { 'simple' => 'upper', 'integer' => 0, 'positive' => 0});

vlog2;
set_timeout();

$status = "OK";

list_elasticsearch_nodes();

my $url = "/_nodes/$node/stats";
$json = curl_elasticsearch $url;

my %nodes = get_field_hash("nodes");
unless(%nodes){
    quit "UNKNOWN", "no nodes stats returned by elasticsearch!" . ( $node ? " Did you specify an incorrect node name? See the 3rd column of --list-nodes" : "" );
}

# escape any dots in node name to not separate
if(scalar keys %nodes > 1){
    quit "UNKNOWN", "more than one node returned for '$node'. You have probably specified the hostname/FQDN/IP which may host multiple clients on the same machine such as LogStash client nodes, rather than the unique instance's Elasticsearch node name, which can be found via --list-nodes";
}
$json = get_field("nodes." . (keys %nodes)[0]);
$msg = "node '$node'";

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
        foreach(my $i=0; $i < scalar @{$val}; $i++){
            recurse_stats("$key$i", $$val[$i]);
        }
    } else {
        return if $key =~ /timestamp$/;
        vlog2 "$key=$val";
        $msg  .= " $key=$val";
        if(isFloat($val)){
            $msg2 .= " '$key'=$val";
        }
        if($verbose){
            if($key =~ /[\b_]bytes$/ and isFloat($val) and $val > 1024){ # KB or above
                $msg .= " (" . human_units($val) . ")";
            }
        }
        $msg2 .= perf_suffix($key);
    }
}

sub get_all_stats(){
    recurse_stats("", $json);
    vlog2;
}

# Only apply thresholds to a single stat, the first key for which a float is detected
my $float_already_detected = 0;
sub get_stat($){
    my $key = shift;
    my $value;
    # not enforcing get_field_float because we may want to just pull the path
    $value = get_field($key);
    $msg .= " $key=$value";
    if(isFloat($value)){
        $msg2 .= " '$key'=$value";
        $msg2 .= perf_suffix($key);
        unless($float_already_detected){
            check_thresholds($value);
            $msg2 .= msg_perf_thresholds(1);
        }
        $float_already_detected = 1;
    }
}

plural $num_keys;
$msg .= " stat$plural:";
if($num_keys == 1){
    get_stat($keys[0]);
} elsif(@keys){
    foreach my $key (@keys){
        get_stat($key);
    }
} else {
    get_all_stats();
}

$msg .= " |$msg2" if $msg2;

vlog2;
quit $status, $msg;
