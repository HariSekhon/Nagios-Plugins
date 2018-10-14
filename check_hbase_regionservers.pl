#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-28 23:39:55 +0100 (Sun, 28 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of RegionServers that are dead or alive using HBase Stargate Rest API (Thrift API doesn't support this information at time of writing)

Checks the number of dead RegionServers against warning/critical thresholds and lists the dead RegionServers

Tested on CDH 4.x and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1
";

$VERSION = "0.3.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

#set_port_default(20550);
set_port_default(8080);

my $default_warning  = 0;
my $default_critical = 1;

$warning  = $default_warning;
$critical = $default_critical;

env_creds(["HBASE_STARGATE", "HBASE_REST", "HBASE"], "HBase Stargate Rest API Server");

%options = (
    %hostoptions,
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive) for dead regionservers (defaults to $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive) for dead regionservers (defaults to $default_critical)" ],
);

@usage_order = qw/host port warning critical/;
get_options();

$host   = validate_host($host);
$host   = validate_resolvable($host);
$port   = validate_port($port);
my $url = "http://$host:$port/status/cluster";
vlog_option "url", $url;
validate_thresholds();

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $content = curl $url, "HBase Stargate";

$status = "OK";

my $live_servers;
my $dead_servers;
my $average_load;
if($content =~ /(\d+) live servers, (\d+) dead servers, (\d+(?:\.\d+)?|NaN) average load/){
    $live_servers = $1;
    $dead_servers = $2;
    $average_load = $3;
} else {
    quit "CRITICAL", "didn't find live/dead server count line in output from HBase Stargate, try rerunning with -vvv. If the Rest API output has changed plugin may need updating";
}

plural $live_servers;
$msg .= "$live_servers live regionserver$plural";
plural $dead_servers;
if($live_servers < 1){
    critical();
    $msg .= " ($live_servers < 1)";
}
$msg .= ", $dead_servers dead regionserver$plural";
check_thresholds($dead_servers);
$msg .= ", $average_load average load";

my $dead_servers_section = 0;
my @dead_servers;
my $dead_server;
foreach(split("\n", $content)){
    if(/^\d+ dead servers/){
        $dead_servers_section = 1;
    }
    next unless $dead_servers_section;
    if(/^ {4}([^\s,]+)/){
        $dead_server = $1;
        $dead_server =~ s/:\d+$//;
        push(@dead_servers, $dead_server);
    }
}
if(@dead_servers){
    @dead_servers = uniq_array @dead_servers;
    plural scalar @dead_servers;
    $msg .= ". Dead regionserver$plural: " . join(",", @dead_servers);
}
if($average_load eq "NaN"){
    $average_load = 0;
}
$msg .= " | live_regionservers=$live_servers dead_regionservers=$dead_servers;" . get_upper_thresholds() . ";0 hbase_load_average=$average_load";

quit $status, $msg;
