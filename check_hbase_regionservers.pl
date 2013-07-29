#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-28 23:39:55 +0100 (Sun, 28 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the number of RegionServers that are dead or alive using HBase Stargate Rest API (Thrift API doesn't support this information at time of writing)

Checks the number of dead RegionServers against warning/critical thresholds and lists the dead RegionServers";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

my $default_port = 20550;
$port = $default_port;

my $default_warning  = 0;
my $default_critical = 0;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    "H|host=s"         => [ \$host,         "HBase Stargate Rest API server address to connect to" ],
    "P|port=s"         => [ \$port,         "HBase Stargate Rest API server port to connect to (defaults to $default_port)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive) for dead regionservers (defaults to $default_warning)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive) for dead regionservers (defaults to $default_critical)" ],
);

@usage_order = qw/host port warning critical/;
get_options();

$host   = validate_hostname($host);
$port   = validate_port($port);
my $url = "http://$host:$port/status/cluster";
vlog_options "url", $url;
validate_thresholds();

vlog2;
set_timeout();

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->show_progress(1) if $debug;

vlog2 "querying Stargate";
my $res = $ua->get($url);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = my $content_single_line = $res->content;
vlog3 "\ncontent:\n\n$content\n";
$content_single_line =~ s/\n/ /g;
vlog2;

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

$status = "OK";

my $live_servers;
my $dead_servers;
my $average_load;
if($content =~ /(\d+) live servers, (\d+) dead servers, (\d+(?:\.\d+)?) average load/){
    $live_servers = $1;
    $dead_servers = $2;
    $average_load = $3;
} else {
    quit "CRITICAL", "didn't find live/dead server count line in output from HBase Stargate, try rerunning with -vvv. If the Rest API output has changed plugin may need updating";
}

plural $live_servers;
$msg .= "$live_servers live regionserver$plural, ";
plural $dead_servers;
$msg .= "$dead_servers dead regionserver$plural";
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
$msg .= " | live_regionservers=$live_servers dead_regionservers=$dead_servers;" . get_upper_thresholds() . ";0 hbase_load_average=$average_load";

quit $status, $msg;
