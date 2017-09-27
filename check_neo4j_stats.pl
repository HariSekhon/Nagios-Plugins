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

$DESCRIPTION = "Nagios Plugin to check the Neo4j stats of IDs allocated for Nodes, Relationships, Properties etc using the Neo4j REST API

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

my $id;
my @ids;

%options = (
    %hostoptions,
    %useroptions,
    "s|stats=s"        =>  [ \$id,  "stats to return, comma separated. Specify a single stat to check it against warning/critical thresholds. Run without this option to see all available stats" ],
    %thresholdoptions,
    %ssloptions,
);
splice @usage_order, 6, 0, qw/host port stats warning critical/;

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$user  = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
if($id){
    @ids = split(/\s*,\s*/, $id);
    for(my $i=0; $i < scalar @ids; $i++){
        $ids[$i] = validate_alnum($ids[$i], "stat");
    }
    @ids = uniq_array(@ids);
}
validate_thresholds(0, 0, { "simple" => "upper", "positive" => 1, "integer" => 1}) if (scalar @ids == 1);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DPrimitive%20count";

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
defined($json->[0]->{"attributes"}) or quit "UNKNOWN", "'attributes' field not returned by Neo4j! $nagios_plugins_support_msg_api";
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
if(scalar @ids == 1){
    $name  = $ids[0];
    grep ($name, @ids) or quit "CRITICAL", sprintf("stat '%s' was not returned by Neo4j, did you specify an incorrect stat name? Run without --stats to see available stats", $name);
    $value = $stats{$name};
    $msg = sprintf("%s = %s", $name, $value);
    check_thresholds($value);
    $msg .= sprintf(" | %s=%d", $name, $value);
    msg_perf_thresholds();
} elsif(@ids){
    foreach $name (@ids){
        grep({ $name eq $_ } @stats) or quit "CRITICAL", sprintf("stat '%s' was not returned by Neo4j, did you specify an incorrect stat name? Run without --stats to see available stats", $name);
    }
    foreach $name (@stats){
        grep({$name eq $_ } @ids) or next;
        $msg .= sprintf("%s = %s, ", $name, $stats{$name});
    }
    $msg =~ s/, $//;
    $msg .= " | ";
    foreach $name (@stats){
        grep({$name eq $_ } @ids) or next;
        $msg .= sprintf("%s=%d ", $name, $stats{$name});
    }
} else {
    foreach $name (@stats){
        $msg .= sprintf("%s = %s, ", $name, $stats{$name});
    }
    $msg =~ s/, $//;
    $msg .= " | ";
    foreach $name (@stats){
        $msg .= sprintf("%s=%d ", $name, $stats{$name});
    }
}

quit $status, $msg;
