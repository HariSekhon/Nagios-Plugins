#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-01 09:31:46 +0100 (Thu, 01 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check a Mesos Master's health API endpoint";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

set_port_default(5050);

env_creds(["Mesos Master", "Mesos"], "Mesos Master");

%options = (
    %hostoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

vlog2;
set_timeout();

$status = "UNKNOWN";

my $url = "http://$host:$port/master/health";

validate_resolvable($host);
vlog2("querying Mesos Master's health API endpoint");
$main::ua->show_progress(1) if $debug;
my $req = HTTP::Request->new("GET", $url);
my $response = $main::ua->request($req);
my $content  = $response->content;
vlog3("returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n");
vlog2("http status code:     " . $response->code);
vlog2("http status message:  " . $response->message . "\n");

if($response->code eq 200){
    $status = "OK";
} else {
    $status = "CRITICAL";
}
$msg = "Mesos Master health API response: " . $response->code . " " . $response->message;

quit $status, $msg;
