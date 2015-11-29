#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_version.html

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Console version

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %biginsights_options,
    %expected_version_option,
);

get_options();

$host               = validate_host($host);
$port               = validate_port($port);
$user               = validate_user($user);
$password           = validate_password($password);
$expected_version   = validate_regex($expected_version, "expected version") if defined($expected_version);
validate_ssl();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

my $url = "$url_prefix/$api/configuration/getVersion";

# curl_biginsights expects json and version is returned as plain html
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
