#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-05-26 17:24:31 +0100 (Mon, 26 May 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the Neo4j data store sizes using the Neo4j REST API

Tested on Neo4j 1.9, 2.0, 2.3, 3.0, 3.1, 3.2";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
#use Data::Dumper;
use JSON;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(7474);

env_creds("Neo4j");

my $store;
my @stores;

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    "s|stores=s"        =>  [ \$store,  "Stores to return size information for, comma separated. Specify a single store to check it's size against warning/critical thresholds in bytes. Run without this option to see all available stores" ],
    %thresholdoptions,
);
@usage_order = qw/host port stores warning critical/;

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$user  = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
if($store){
    @stores = split(/\s*,\s*/, $store);
    for(my $i=0; $i < scalar @stores; $i++){
        $stores[$i] = validate_alnum($stores[$i], "store");
    }
    @stores = uniq_array(@stores);
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1}) if (scalar @stores == 1);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DStore%20file%20sizes";

my $content = curl $url, "Neo4j", $user, $password;
my $json;
try {
    $json = decode_json($content);
};
catch {
    quit "CRITICAL", "invalid json returned by Neo4j at '$url_prefix'. Try with -vvv to see full output";
};

#vlog3(Dumper($json));
isArray($json) or quit "UNKNOWN", "output returned by Neo4j is not structured in output array. $nagios_plugins_support_msg_api";
defined($json->[0]->{"attributes"}) or quit "UNKNOWN", "'attributes' field not returned by Neo4j! Perhaps this is Neo4j 1.x (see check_neo4j_version.pl)? Otherwise $nagios_plugins_support_msg_api";
isArray($json->[0]->{"attributes"}) or quit "UNKNOWN", "attributes field returned by Neo4j is not an array as expected! $nagios_plugins_support_msg_api";

my %stats;
my @stats;
foreach my $item (@{$json->[0]{"attributes"}}){
    foreach(qw/name value/){
        defined($item->{$_}) or quit "UNKNOWN", "'$-' field not returned for items in 'attributes' by Neo4j! $nagios_plugins_support_msg_api";
    }
    $stats{$item->{"name"}} = $item->{"value"};
    push(@stats, $item->{"name"});
}

my $name;
my $value;
if(scalar @stores == 1){
    $name  = $stores[0];
    grep ($name, @stats) or quit "CRITICAL", sprintf("store '%s' was not returned by Neo4j, did you specify an incorrect store name? Run without --stores to see available stores", $name);
    $value = $stats{$name};
    $msg = sprintf("%s = %s", $name, human_units($value));
    check_thresholds($value);
    $msg .= sprintf(" | %s=%db", $name, $value);
    msg_perf_thresholds();
} elsif(@stores){
    foreach $name (@stores){
        grep({ $name eq $_ } @stats) or quit "CRITICAL", sprintf("store '%s' was not returned by Neo4j, did you specify an incorrect store name? Run without --stores to see available stores", $name);
    }
    foreach $name (@stats){
        grep({$name eq $_ } @stores) or next;
        $msg .= sprintf("%s = %s, ", $name, human_units($stats{$name}));
    }
    $msg =~ s/, $//;
    $msg .= " | ";
    foreach $name (@stats){
        grep({$name eq $_ } @stores) or next;
        $msg .= sprintf("%s=%db ", $name, $stats{$name});
    }
} else {
    foreach $name (@stats){
        $msg .= sprintf("%s = %s, ", $name, human_units($stats{$name}));
    }
    $msg =~ s/, $//;
    $msg .= " | ";
    foreach $name (@stats){
        $msg .= sprintf("%s=%db ", $name, $stats{$name});
    }
}

quit $status, $msg;
