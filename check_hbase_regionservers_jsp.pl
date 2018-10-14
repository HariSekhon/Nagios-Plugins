#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-29 01:35:11 +0100 (Mon, 29 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of RegionServers that are dead or alive using the HBase Master JSP

Checks the number of dead RegionServers against warning/critical thresholds and lists the dead RegionServers

Recommended to use check_hbase_regionservers.pl instead which uses the HBase Stargate Rest API since parsing the JSP is very brittle and could easily break between versions

Tested on CDH 4.3 (HBase 0.94) and Apache HBase 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1
";

$VERSION = "0.5.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

#set_port_default(60010);
set_port_default(16010);

my $default_warning  = 0;
my $default_critical = 1;
$warning  = $default_warning;
$critical = $default_critical;

env_creds(["HBASE_MASTER", "HBASE"], "HBase Master");

%options = (
    %hostoptions,
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port user password warning critical/;
get_options();

$host = validate_host($host);
$host = validate_resolvable($host);
$port = validate_port($port);
my $url = "http://$host:$port/master-status";
vlog_option "url", $url;

validate_thresholds();

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $content = curl $url, "HBase Master JSP";

my $live_servers_section = 0;
my $dead_servers_section = 0;
my $live_servers;
my $dead_servers;
my @dead_servers;
my $dead_server;
foreach(split("\n", $content)){
    if(/Region Servers/){
        $live_servers_section = 1;
    }
    next unless $live_servers_section;
    if(/Dead Region Servers/){
        $live_servers_section = 0;
        last;
    }
    # HBase 0.94
    #if(/<tr><th>Total: <\/th><td>servers: (\d+)<\/td>/){
    # HBase 1.0
    #if(/<tr><td>Total:(\d+)<\/td>/){
    # trying to make backwards compatible with original match
    if(/<tr>\s*<t[dh]>Total:\s*(?:<\/th>\s*<td>servers:)?\s*(\d+)<\/td>/){
        $live_servers = $1;
        last;
    }
    last if /<\/table>/;
}
# This is the best we can do with the JSP unfortunately since it outputs nothing when there are no live regionservers
defined($live_servers) or $live_servers = 0;
#quit "UNKNOWN", "failed to find live server count, JSP format may have changed, try re-running with -vvv, plugin may need updating" unless defined($live_servers);

foreach(split("\n", $content)){
    if(/Dead Region Servers/){
        $dead_servers_section = 1;
    }
    next unless $dead_servers_section;
    if(/<td>([^,]+),\d+,\d+<\/td>/){
        $dead_server = $1;
        push(@dead_servers, $dead_server);
    } elsif(/<tr><th>Total: <\/th><td>servers: (\d+)<\/td><\/tr>/){
        $dead_servers = $1;
        last;
    }
    last if /<\/table>/;
    last if /Regions in Transition/;
}
# This is the best we can do with the JSP unfortunately since it outputs nothing when there are no dead regionservers
defined($dead_servers) or $dead_servers = 0;
#quit "UNKNOWN", "failed to find dead server count, JSP format may have changed, try re-running with -vvv, plugin may need updating" unless defined($dead_servers);

plural $live_servers;
$msg .= "$live_servers live regionserver$plural";
if($live_servers < 1){
    critical();
    $msg .= " ($live_servers < 1)";
}
plural $dead_servers;
$msg .= ", $dead_servers dead regionserver$plural";
check_thresholds($dead_servers);

if(@dead_servers){
    @dead_servers = uniq_array @dead_servers;
    plural scalar @dead_servers;
    $msg .= ". Dead regionserver$plural: " . join(",", @dead_servers);
}
$msg .= " | live_regionservers=$live_servers dead_regionservers=$dead_servers;" . get_upper_thresholds() . ";0";

quit $status, $msg;
