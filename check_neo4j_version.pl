#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-05-26 19:41:43 +0100 (Mon, 26 May 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Neo4j version using the Neo4j REST API

Tested on Neo4j 1.9, 2.0, 2.3, 3.0, 3.1, 3.2";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON;
use LWP::Simple '$ua';

set_port_default(7474);

env_creds("Neo4j");

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %expected_version_option,
    %ssloptions,
);
@usage_order = qw/host port expected/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
$user = validate_user($user) if defined($user);
$password = validate_password($password) if defined($password);
$expected_version = validate_regex($expected_version, "expected version") if defined($expected_version);
validate_ssl();

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/db/data";

my $content = curl $url, "Neo4j", $user, $password;
my $json;
try {
    $json = decode_json($content);
};
catch {
    quit "CRITICAL", "invalid json returned by Neo4j at '$url_prefix'. Try with -vvv to see full output";
};

defined($json->{"neo4j_version"}) or quit "UNKNOWN", "'neo4j_version' not returned by Neo4j. $nagios_plugins_support_msg_api";
my $neo4j_version = $json->{"neo4j_version"};

$msg = "Neo4j version $neo4j_version";

if(defined($expected_version) and $neo4j_version !~ $expected_version){
    critical;
    $msg .= " (expected: $expected_version)";
}

quit $status, $msg;
