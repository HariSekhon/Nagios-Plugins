#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-03 00:25:49 +0000 (Tue, 03 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to show Datameer stats on number of Workbooks, Connections (Data Connectors), Import and Export Jobs, Dashboards and Infographics using the Datameer Rest API

Outputs perfdata for Nagios graphing of these usage trends over time

Tested against Datameer 2.1.4.6 and 3.0.11";

$VERSION = "0.2";

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

my $job_id;

%options = (
    "H|host=s"         => [ \$host,         "Datameer server" ],
    "P|port=s"         => [ \$port,         "Datameer port (default: $default_port)" ],
    "u|user=s"         => [ \$user,         "User to connect with (\$DATAMEER_USER)" ],
    "p|password=s"     => [ \$password,     "Password to connect with (\$DATAMEER_PASSWORD)" ],
);

@usage_order = qw/host port user password/;

env_creds("DATAMEER");

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

$status = "OK";

$msg = "";
my $content;
my $json;
my %num;
foreach(qw/workbook connections import-job export-job dashboard infographics/){
    my $url = "http://$host:$port/rest/$_";

    vlog2;

    $content = curl $url, $user, $password;

    $json;
    try{
        $json = decode_json $content;
    };
    catch{
        quit "CRITICAL", "invalid json returned by '$host:$port'";
    };

    $num{$_} = scalar @{$json};
    $msg .= "$_=$num{$_} ";
}

$msg .= "| $msg";

quit $status, $msg;
