#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the Datameer version using the Datameer Rest API

Tested against Datameer 2.1.4.6 and 3.0.11";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $default_port = 8080;
$port = $default_port;

my $expected;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
    "e|expected=s"     => [ \$expected,     "Expected version regex, raises CRITICAL if not matching, optional" ],
);

@usage_order = qw/host port user password warning critical/;

env_creds("DATAMEER");

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
$expected   = validate_regex($expected, "expected version") if defined($expected);

my $url = "http://$host:$port/rest/license-details";

vlog2;
set_timeout();

$status = "OK";

my $content = curl $url, $user, $password;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "CRITICAL", "invalid json returned by '$host:$port'";
};

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

vlog2 if is_ok;
quit $status, $msg;
