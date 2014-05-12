#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Console version

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

set_port_default(8080);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api = "data/controller";

our $protocol = "http";
my  $url;

%options = (
    %hostoptions,
    %useroptions,
    %expected_version_option,
    %tlsoptions,
);
@usage_order = qw/host port user password expected tls ssl-CA-path tls-noverify/;

get_options();

$host               = validate_host($host);
$port               = validate_port($port);
$user               = validate_user($user);
$password           = validate_password($password);
$expected_version   = validate_regex($expected_version, "expected version") if defined($expected_version);

tls_options();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

$url = "$url_prefix/$api/configuration/getVersion";

# my query_BI_console() sub enforces json and version is returned as html
my $html = curl $url, "IBM BigInsights Console", $user, $password;

my $biginsights_version = trim($html);
$msg = $biginsights_version;
my $version_format_regex = qw/IBM.+BigInsights.+\d+\.\d+\.\d+/;
$biginsights_version =~ $version_format_regex or quit "UNKNOWN", "version string did not match expected regex ($version_format_regex), returned version: $msg";
if(defined($expected_version) and $biginsights_version !~ $expected_version){
    critical;
    $msg .= " (expected: $expected_version)";
}

quit $status, $msg;
