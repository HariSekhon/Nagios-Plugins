#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-04 02:44:22 +0000 (Mon, 04 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check the Heap used on a single Cassandra node using nodetool.

Can specify a remote host and port otherwise it checks the local node's stats (for calling over NRPE on each Cassandra node)

Written and tested against Cassandra 2.0, DataStax Community Edition";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Cassandra;

my $default_warning  = 80;
my $default_critical = 90;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    %nodetool_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold max % Heap used (inclusive. Default: $default_warning)"  ],
    "c|critical=s"     => [ \$critical,     "Critical threshold max % Heap used (inclusive. Default: $default_critical)" ],
);

@usage_order = qw/nodetool host port user password warning critical/;
get_options();

$nodetool = validate_nodetool($nodetool);
$host     = validate_host($host)         if defined($host);
$port     = validate_port($port)         if defined($port);
$user     = validate_user($user)         if defined($user);
$password = validate_password($password) if defined($password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 0, "positive" => 1, "max" => 100 });

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}info";

vlog2 "fetching cluster node heap information";
if(defined($host)){
    validate_resolvable($host);
}
my @output = cmd($cmd);

my $heap_used;
my $heap_total;
my $heap_units;
foreach(@output){
    if(/^\s*Heap\s*Memory\s*\((\w+)\)\s*:\s*(\d+(?:\.\d+)?)\s*\/\s*(\d+(?:\.\d+)?)/){
        $heap_units = $1;
        $heap_used  = $2;
        $heap_total = $3;
        last;
    }
}
quit "UNKNOWN", "failed to determine heap used from nodetool output"  unless(defined($heap_used));
quit "UNKNOWN", "failed to determine heap total from nodetool output" unless(defined($heap_total));
quit "UNKNOWN", "failed to determine heap units from nodetool output" unless(defined($heap_units));

my $heap_used_percent = sprintf("%.2f", $heap_used / $heap_total * 100);

$msg = "$heap_used_percent% heap used ($heap_used/$heap_total $heap_units)";
check_thresholds($heap_used_percent);
$msg .= " | heap_used_percentage=$heap_used_percent%";
msg_perf_thresholds();
$heap_units = isNagiosUnit($heap_units) || "";
$msg .= " heap_used=$heap_used$heap_units heap_total=$heap_total$heap_units";

quit $status, $msg;
