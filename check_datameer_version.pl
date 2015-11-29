#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the Datameer version using the Datameer Rest API

Tested against Datameer 2.1.4.6, 3.0.11 and 3.1.1";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected;

%options = (
    %datameer_options,
    "e|expected=s"     => [ \$expected,     "Expected version regex, raises CRITICAL if not matching, optional" ],
);

@usage_order = qw/host port user password warning critical/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$expected = validate_regex($expected, "expected version") if defined($expected);

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

my $json = datameer_curl $url, $user, $password;

unless(defined($json->{"ProductVersion"})){
    quit "UNKNOWN", "ProductVersion was not defined in json output returned from Datameer server. Format may have changed. $nagios_plugins_support_msg";
}
my $datameer_version = $json->{"ProductVersion"};

$datameer_version =~ /^\d+(\.\d+)+$/ or quit "UNKNOWN", "unrecognized Datameer version, expecting x.y.z.. format. Format may have changed. $nagios_plugins_support_msg";

$msg = "Datameer version is '$datameer_version'";
if(defined($expected) and $datameer_version !~ /^$expected$/){
    critical;
    $msg .= " (expected: $expected)";
}

quit $status, $msg;
