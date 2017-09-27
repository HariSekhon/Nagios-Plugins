#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-05-26 19:16:56 +0100 (Mon, 26 May 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check whether a Neo4j instance is Read Only using the Neo4j REST API

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

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
);

get_options();

$host  = validate_host($host);
$port  = validate_port($port);
$user  = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/db/manage/server/jmx/domain/org.neo4j/instance%3Dkernel%230%2Cname%3DKernel";

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

my $ReadOnly;
foreach my $item (@{$json->[0]{"attributes"}}){
    foreach(qw/name value/){
        defined($item->{$_}) or quit "UNKNOWN", "'$-' field not returned for items in 'attributes' by Neo4j! $nagios_plugins_support_msg_api";
    }
    next unless $item->{"name"} eq "ReadOnly";
    $ReadOnly = $item->{"value"};
    last;
}

defined($ReadOnly) or quit "UNKNOWN", "failed to find ReadOnly in output from Neo4j. $nagios_plugins_support_msg_api";

$msg = "Neo4j instance ";
if($ReadOnly){
    critical;
    $msg .= "is READ ONLY";
} else {
    $msg .= "is not read only";
}

quit $status, $msg;
