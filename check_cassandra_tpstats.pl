#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-15 04:56:49 +0100 (Tue, 15 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to parse Cassandra's 'nodetool tpstats' for Nagios graphing

TODO: add alerting for Dropped, Pending, Blocked etc

Written against Cassandra 2.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $nodetool = "nodetool";

%options = (
    "n|nodetool=s"         => [ \$nodetool,         "Path to 'nodetool' command if not in \$PATH ($ENV{PATH})" ],
);

@usage_order = qw/nodetool/;
get_options();

$nodetool = validate_filename($nodetool, 0, "nodetool");
$nodetool =~ /(?:^|\/)nodetool$/ or usage "invalid path to nodetool, must end in nodetool";
which($nodetool, 1);

vlog2;
set_timeout();

$status = "OK";

my @output = cmd("$nodetool tpstats");

my $format_changed_err = "unrecognized header line '%s', nodetool output format may have changed, aborting. ";
sub die_format_changed($){
    quit "UNKNOWN", sprintf("$format_changed_err$nagios_plugins_support_msg", $_[0]);
}

$output[0] =~ /Pool\s+Name\s+Active\s+Pending\s+Completed\s+Blocked\s+All time blocked\s*$/i or die_format_changed($output[0]);
my @stats;
foreach(@output[1..15]){
    /^(\w+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s+(\d+)\s*$/ or die_format_changed($_);
    push(@stats,
        (
            { "$1_Active"           => $2, },
            { "$1_Pending"          => $3, },
            { "$1_Completed"        => $4, },
            { "$1_Blocked"          => $5, },
            { "$1_All_time_blocked" => $6, },
        )
    );
}
my $lineno = 16;
foreach(; $lineno < scalar @output; $lineno += 1){
    next if $output[$lineno] =~ /^\s*$/;
    last;
}

$output[$lineno] =~ /^Message type\s+Dropped/ or die_format_changed($output[$lineno]);
$lineno += 1;
foreach(; $lineno < scalar @output; $lineno += 1){
    $output[$lineno] =~ /^(\w+)\s+(\d+)$/ or die_format_changed($output[$lineno]);
    push(@stats,
        (
            { "$1_Dropped" => $2 }
        )
    );
}

foreach(my $i = 0; $i < scalar @stats; $i++){
    foreach my $stat2 ($stats[$i]){
        foreach my $key (keys %$stat2){
            $msg .= "$key=$$stat2{$key} ";
        }
    }
}
$msg .= "| $msg";

quit $status, $msg;
