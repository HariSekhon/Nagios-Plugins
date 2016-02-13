#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-17 22:35:14 +0000 (Tue, 17 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given MongoD is Master via REST API

Authentication not supported yet, and Rest API is not recommended anyway.

Tested on MongoDB 2.6.1, 3.2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MongoDB;
use LWP::Simple '$ua';

set_port_default(28017);

%options = (
    %hostoptions,
#    %useroptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
#$user = validate_user($user) if defined($user) and defined($password);
#$password = validate_password($password) if defined($password);

vlog2;
set_timeout();

$status = "OK";

$json = curl_mongo "isMaster?text=1";

my $ismaster = get_field("ismaster") ? "true" : "false";

$msg = "mongodb://$host:$port ismaster: $ismaster";
critical unless $ismaster eq "true";

quit $status, $msg;
