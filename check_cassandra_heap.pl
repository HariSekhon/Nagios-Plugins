#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-04 02:44:22 +0000 (Mon, 04 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the Heap used on a single Cassandra node using nodetool.

Can specify a remote host and port otherwise it checks the local node's heap (for calling over NRPE on each Cassandra node)

Tested on Cassandra 1.2, 2.0, 2.1, 2.2, 3.0, 3.5, 3.6, 3.7, 3.9, 3.10, 3.11";

$VERSION = "0.2.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Cassandra::Nodetool;

set_threshold_defaults(80, 90);

%options = (
    %nodetool_options,
    %thresholdoptions,
);
splice @usage_order, 0, 0, 'nodetool';

get_options();

($nodetool, $host, $port, $user, $password) = validate_nodetool_options($nodetool, $host, $port, $user, $password);
validate_thresholds(undef, undef, { "simple" => "upper", "integer" => 0, "positive" => 1, "max" => 100 });

vlog2;
set_timeout();

$status = "OK";

my $options = nodetool_options($host, $port, $user, $password);
my $cmd     = "${nodetool} ${options}info";

vlog2 "fetching cluster node heap information";
my @output = cmd($cmd);

my %heap = ( units => undef, used => undef, total => undef);
foreach(@output){
    check_nodetool_errors($_);
    # issue #99 - user had comma separator instead of dot that prevented heap values being found
    if(/^\s*Heap\s*Memory\s*\((\w+)\)\s*:\s*(\d+(?:[.,]\d+)?)\s*\/\s*(\d+(?:[.,]\d+)?)/){
        $heap{"units"} = $1;
        $heap{"used"}  = $2;
        $heap{"total"} = $3;
        $heap{"used"} =~ s/,/./;
        $heap{"total"} =~ s/,/./;
        last;
    }
}
foreach(sort keys %heap){
    quit "UNKNOWN", "failed to determine heap $_ from nodetool output"  unless(defined($heap{$_}));
}

my $heap_used_percent = sprintf("%.2f", $heap{"used"} / $heap{"total"} * 100);

$msg = "$heap_used_percent% heap used ($heap{used}/$heap{total} $heap{units})";
check_thresholds($heap_used_percent);
$msg .= " | 'heap_used_%'=$heap_used_percent%";
msg_perf_thresholds();
$heap{"units"} = isNagiosUnit($heap{"units"}) || "";
$msg .= " heap_used=$heap{used}$heap{units} heap_total=$heap{total}$heap{units}";

vlog2;
quit $status, $msg;
