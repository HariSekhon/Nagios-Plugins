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

$DESCRIPTION = "Nagios Plugin to parse Cassandra's 'nodetool tpstats' for Pending/Blocked operations, as well as also graphing Active and Dropped operations.

Call over NRPE on each Cassandra node, check the baseline first and then set appropriate thresholds to alert on too many Pending/Blocked operations which is indicative of performance problems.

Written and tested against Cassandra 2.0, DataStax Community Edition";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $nodetool = "nodetool";

my $default_warning  = 0;
my $default_critical = 0;

$warning  = $default_warning;
$critical = $default_critical;

%options = (
    "n|nodetool=s"  => [ \$nodetool, "Path to 'nodetool' command if not in \$PATH ($ENV{PATH})" ],
    "w|warning=s"   => [ \$warning,  "Warning  threshold max (inclusive) for Pending/Blocked operations (default: $default_warning)"  ],
    "c|critical=s"  => [ \$critical, "Critical threshold max (inclusive) for Pending/Blocked operations (default: $default_critical)" ],
);

@usage_order = qw/nodetool warning critical/;
get_options();

$nodetool = validate_filename($nodetool, 0, "nodetool");
$nodetool =~ /(?:^|\/)nodetool$/ or usage "invalid path to nodetool, must end in nodetool";
which($nodetool, 1);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

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
            { "$1_Blocked"          => $5, },
            { "$1_Pending"          => $3, },
            { "$1_Active"           => $2, },
            #{ "$1_Completed"        => $4, },
            #{ "$1_All_time_blocked" => $6, },
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
my @stats2;
foreach(; $lineno < scalar @output; $lineno += 1){
    $output[$lineno] =~ /^(\w+)\s+(\d+)$/ or die_format_changed($output[$lineno]);
    push(@stats2,
        (
            { ucfirst(lc($1)) . "_Dropped" => $2 }
        )
    );
}

push(@stats2, @stats);

my $msg2;
my $msg3;
foreach(my $i = 0; $i < scalar @stats2; $i++){
    foreach my $stat3 ($stats2[$i]){
        foreach my $key (keys %$stat3){
            $msg2 = "$key=$$stat3{$key} ";
            $msg3 .= $msg2;
            if($key =~ /Pending|Blocked/i){
                unless(check_thresholds($$stat3{$key}, 1)){
                    $msg2 = uc $msg2;
                }
            }
            $msg .= $msg2;
        }
    }
}
$msg  =~ s/\s$//;
if($verbose or $status ne "OK"){
    msg_thresholds();
}
$msg .= "| $msg3";

quit $status, $msg;
