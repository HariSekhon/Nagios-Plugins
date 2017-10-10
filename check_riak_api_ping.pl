#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 02:09:23 +0100 (Sun, 21 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check Riak's ping API returns OK

Tested on Riak 1.4.0, 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.1.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';
use JSON::XS;

set_port_default(8098);

env_creds("Riak");

my $metrics;
my $all_stats;
my $expected;

%options = (
    %hostoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

$host = validate_resolvable($host);
my $url = "http://$host:$port/ping";

my $content = curl $url, "Riak node $host";
$content = strip($content);

$msg = "Riak API Ping ";

if($content =~ /^\s*OK\s*$/im){
    $status = "OK";
    $msg .= "= 'OK'";
} else {
    critical();
    $msg .= "!= OK";
}

quit $status, $msg;
