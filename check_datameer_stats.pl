#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-03 00:25:49 +0000 (Tue, 03 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to show Datameer stats on number of Workbooks, Connections (Data Connectors), Import and Export Jobs, Dashboards and Infographics using the Datameer Rest API

Outputs perfdata for Nagios graphing of these usage trends over time

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

my $job_id;

%options = (
    %datameer_options,
);

@usage_order = qw/host port user password/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);

set_timeout();
set_http_timeout($timeout/3); # divided by 6 is a bit tight since the first request may be slower than the others and trip timeout

$status = "OK";

$msg = "";
my $json;
my %num;
my $url;
#my $stat;
# Datameer 3.0 no longer supports user management via the Rest API
# user-management\/users user-management\/groups user-management\/roles/){
foreach(qw/workbook connections import-job export-job dashboard infographics/){
    $url = "http://$host:$port/rest/$_";

    $json = datameer_curl $url, $user, $password;

    $num{$_} = scalar @{$json};
    #($stat = $_ ) =~ s/.*\///;
    #$msg .= "$stat=$num{$_} ";
    $msg .= "$_=$num{$_} ";
}

$msg .= "| $msg";

quit $status, $msg;
