#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-05-16 17:57:18 +0100 (Mon, 16 May 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to show the Nagios stats with perfdata for graphing purposes";

$VERSION = "0.4.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $nagiostats_default = "nagiostats";

my $nagiostats = $nagiostats_default;
my $stats;
my $config_file;
my $stats_file;
my %vars;

%options = (
    "s|stats=s"       => [ \$stats, "Select which batch of stats to collect from: all,overview,checkcounts,checklatency" ],
    "c|config=s"      => [ \$config_file, "Specifies path to main Nagios config file. Optional" ],
    "f|statsfile=s"   => [ \$stats_file,  "Specifies path to Nagios stats file. Optional" ],
    "n|nagiostats=s"  => [ \$nagiostats,  "Path to nagiostats program (defaults to $nagiostats_default)" ],
);
@usage_order = qw/stats config statsfile nagiostats/;

get_options();

defined($stats) or usage "please choose which group of stats to output";
my @stats = split(",", $stats);
$config_file = validate_file($config_file) if $config_file;
$stats_file  = validate_file($stats_file)  if $stats_file;
if(defined($config_file) and defined($stats_file)){
    quit "UNKNOWN", "Config file and stats file cannot be the same file!" if($config_file eq $stats_file);
}
$nagiostats = validate_filename($nagiostats);
$nagiostats =~ /nagiostats$/ or usage "invalid program given for nagiostats";

vlog2 "stats group:    $stats";
vlog2 "config file:    $config_file" if $config_file;
vlog2 "stats file:     $stats_file"  if $stats_file;
vlog2 "WARNING: there is a BUG in nagiostats 3.2.1 that causes all counters to be returned with ZEROs when you supply the stats file even if it's the same file path as is default. This is not the fault of this code as it merely uses nagiostats to get the information from nagios" if $stats_file;

set_timeout();

# nagiostats -h lists the MRTG variables available
#
# STATUSFILEAGETT      string with age of status data file (time_t format).
# TOTCMDBUF            total number of external command buffer slots available.
# USEDCMDBUF           number of external command buffer slots currently in use.
# HIGHCMDBUF           highest number of external command buffer slots ever in use.
# NUMSERVICES          total number of services.
# NUMHOSTS             total number of hosts.
# NUMSVCOK             number of services OK.
# NUMSVCWARN           number of services WARNING.
# NUMSVCUNKN           number of services UNKNOWN.
# NUMSVCCRIT           number of services CRITICAL.
# NUMSVCPROB           number of service problems (WARNING, UNKNOWN or CRITIAL).
# NUMSVCCHECKED        number of services that have been checked since start.
# NUMSVCSCHEDULED      number of services that are currently scheduled to be checked.
# NUMSVCFLAPPING       number of services that are currently flapping.
# NUMSVCDOWNTIME       number of services that are currently in downtime.
# NUMHSTUP             number of hosts UP.
# NUMHSTDOWN           number of hosts DOWN.
# NUMHSTUNR            number of hosts UNREACHABLE.
# NUMHSTPROB           number of host problems (DOWN or UNREACHABLE).
# NUMHSTCHECKED        number of hosts that have been checked since start.
# NUMHSTSCHEDULED      number of hosts that are currently scheduled to be checked.
# NUMHSTFLAPPING       number of hosts that are currently flapping.
# NUMHSTDOWNTIME       number of hosts that are currently in downtime.
#
# NUMHSTACTCHK1M       number of hosts actively checked in last 1/5/15/60 minutes.
# NUMHSTPSVCHK1M       number of hosts passively checked in last 1/5/15/60 minutes.
# NUMSVCACTCHK1M       number of services actively checked in last 1/5/15/60 minutes.
# NUMSVCPSVCHK1M       number of services passively checked in last 1/5/15/60 minutes.
#
# MAXACTSVCLAT         MIN/MAX/AVG active service check latency (ms).
# MAXACTSVCEXT         MIN/MAX/AVG active service check execution time (ms).
# MAXACTSVCPSC         MIN/MAX/AVG active service check % state change.
# MAXPSVSVCLAT         MIN/MAX/AVG passive service check latency (ms).
# MAXPSVSVCPSC         MIN/MAX/AVG passive service check % state change.
# MAXSVCPSC            MIN/MAX/AVG service check % state change.
# MAXACTHSTLAT         MIN/MAX/AVG active host check latency (ms).
# MAXACTHSTEXT         MIN/MAX/AVG active host check execution time (ms).
# MAXACTHSTPSC         MIN/MAX/AVG active host check % state change.
# MAXPSVHSTLAT         MIN/MAX/AVG passive host check latency (ms).
# MAXPSVHSTPSC         MIN/MAX/AVG passive host check % state change.
# MAXHSTPSC            MIN/MAX/AVG host check % state change.
#
# AVGACTSVCLAT         MIN/MAX/AVG active service check latency (ms).
# AVGACTSVCEXT         MIN/MAX/AVG active service check execution time (ms).
# AVGACTSVCPSC         MIN/MAX/AVG active service check % state change.
# AVGPSVSVCLAT         MIN/MAX/AVG passive service check latency (ms).
# AVGPSVSVCPSC         MIN/MAX/AVG passive service check % state change.
# AVGSVCPSC            MIN/MAX/AVG service check % state change.
# AVGACTHSTLAT         MIN/MAX/AVG active host check latency (ms).
# AVGACTHSTEXT         MIN/MAX/AVG active host check execution time (ms).
# AVGACTHSTPSC         MIN/MAX/AVG active host check % state change.
# AVGPSVHSTLAT         MIN/MAX/AVG passive host check latency (ms).
# AVGPSVHSTPSC         MIN/MAX/AVG passive host check % state change.
# AVGHSTPSC            MIN/MAX/AVG host check % state change.
#
# NUMACTHSTCHECKS1M    number of total active host checks occuring in last 1/5/15 minutes.
# NUMOACTHSTCHECKS1M   number of on-demand active host checks occuring in last 1/5/15 minutes.
# NUMCACHEDHSTCHECKS1M number of cached host checks occuring in last 1/5/15 minutes.
# NUMSACTHSTCHECKS1M   number of scheduled active host checks occuring in last 1/5/15 minutes.
# NUMPARHSTCHECKS1M    number of parallel host checks occuring in last 1/5/15 minutes.
# NUMSERHSTCHECKS1M    number of serial host checks occuring in last 1/5/15 minutes.
# NUMPSVHSTCHECKS1M    number of passive host checks occuring in last 1/5/15 minutes.
# NUMACTSVCCHECKS1M    number of total active service checks occuring in last 1/5/15 minutes.
# NUMOACTSVCCHECKS1M   number of on-demand active service checks occuring in last 1/5/15 minutes.
# NUMCACHEDSVCCHECKS1M number of cached service checks occuring in last 1/5/15 minutes.
# NUMSACTSVCCHECKS1M   number of scheduled active service checks occuring in last 1/5/15 minutes.
# NUMPSVSVCCHECKS1M    number of passive service checks occuring in last 1/5/15 minutes.
# NUMEXTCMDS1M         number of external commands processed in last 1/5/15 minutes.
#
# Note: Replace x's in MRTG variable names with 'MIN', 'MAX', 'AVG', or the
#       the appropriate number (i.e. '1', '5', '15', or '60').
#

@{$vars{"overview"}} = qw/STATUSFILEAGETT
TOTCMDBUF
USEDCMDBUF
HIGHCMDBUF
NUMSERVICES
NUMHOSTS
NUMSVCOK
NUMSVCWARN
NUMSVCUNKN
NUMSVCCRIT
NUMSVCPROB
NUMSVCCHECKED
NUMSVCSCHEDULED
NUMSVCFLAPPING
NUMSVCDOWNTIME
NUMHSTUP
NUMHSTDOWN
NUMHSTUNR
NUMHSTPROB
NUMHSTCHECKED
NUMHSTSCHEDULED
NUMHSTFLAPPING
NUMHSTDOWNTIME/;

@{$vars{"checkcounts"}} = qw/NUMHSTACTCHK1M
NUMHSTPSVCHK1M
NUMSVCACTCHK1M
NUMSVCPSVCHK1M
NUMACTHSTCHECKS1M
NUMOACTHSTCHECKS1M
NUMCACHEDHSTCHECKS1M
NUMSACTHSTCHECKS1M
NUMPARHSTCHECKS1M
NUMSERHSTCHECKS1M
NUMPSVHSTCHECKS1M
NUMACTSVCCHECKS1M
NUMOACTSVCCHECKS1M
NUMCACHEDSVCCHECKS1M
NUMSACTSVCCHECKS1M
NUMPSVSVCCHECKS1M
NUMEXTCMDS1M/;

@{$vars{"checklatency"}} = qw/MAXACTSVCLAT
MAXACTSVCEXT
MAXACTSVCPSC
MAXPSVSVCLAT
MAXPSVSVCPSC
MAXSVCPSC
MAXACTHSTLAT
MAXACTHSTEXT
MAXACTHSTPSC
MAXPSVHSTLAT
MAXPSVHSTPSC
MAXHSTPSC
AVGACTSVCLAT
AVGACTSVCEXT
AVGACTSVCPSC
AVGPSVSVCLAT
AVGPSVSVCPSC
AVGSVCPSC
AVGACTHSTLAT
AVGACTHSTEXT
AVGACTHSTPSC
AVGPSVHSTLAT
AVGPSVHSTPSC
AVGHSTPSC/;

@{$vars{"all"}} = ( @{$vars{"overview"}}, @{$vars{"checkcounts"}}, @{$vars{"checklatency"}} );

foreach my $stat (sort @stats){
    if(not grep { $_ eq $stat } (keys %vars)){
        usage "$stat was not recognized as a valid set of stats to collect. Must be one of: " . join(" ", sort keys %vars);
    }
}

vlog2("Configured to collect stat set(s): " . join(" ", sort @stats));
my $opts = "";
my @vars2;
foreach $stats (sort @stats){
    foreach(@{$vars{$stats}}){
        push(@vars2, $_);
        $opts .= "$_,";
    }
}
$opts =~ s/,$//;
my $cmd = "$nagiostats -m -d $opts";
$cmd .= " -c $config_file" if $config_file;
$cmd .= " -s $stats_file"  if $stats_file;
my $status = "OK";
my @output = cmd($cmd, 1); # cmd(,1) will error out on anything other than return code 0

my $msg = "Stats Collected|";
my $index = 0;
my %vars3;
foreach(@output){
    if(not $vars2[$index]){
        quit "UNKNOWN", "more stats output returned than expected";
    }
    quit "UNKNOWN", "blank stat on line" . ($index+1) if $_ =~ /^\s*$/;
    $vars3{$vars2[$index]} = $_;
    $msg .= "$vars2[$index]=$_ ";
    $index++;
}
$msg =~ s/\s+$//;

# Sanity Checking
#
# check to see if we got all the stats we expected
foreach(@vars2){
    unless(defined($vars3{$_})){
        quit "UNKNOWN", "failed to get all stats, missing stat for $_";
    }
}

# Extra sanity checking since it you specify the wrong stats file we'll simply get all zeros
# These are some stats that should never be zero
# Covers overview group
foreach(qw/NUMSERVICES NUMHOSTS/){
    if(defined($vars3{$_})){
        quit "UNKNOWN", "sanity checking failed, $_ stat should not be zero! (did you supply the wrong stats file?)" unless $vars3{$_};
    }
}
# Covers checkcounts group
if(defined($vars3{"NUMSVCACTCHK1M"}) and defined($vars3{"NUMSVCPSVCHK1M"})){
    if($vars3{"NUMSVCACTCHK1M"} + $vars3{"NUMSVCPSVCHK1M"} < 1){
        quit "UNKNOWN", "sanity checking failed, NUMSVCACTCHK1M + NUMSVCPSVCHK1M stats should not be less than 1, this means Nagios has NO CHECKS! (did you supply the wrong stats file?)";
    }
}
# Covers checklatency group
if(defined($vars3{"MAXACTSVCLAT"}) and defined($vars3{"MAXPSVSVCLAT"})){
    if($vars3{"MAXACTSVCLAT"} + $vars3{"MAXPSVSVCLAT"} < 0){
        quit "UNKNOWN", "sanity checking failed, MAXACTSVCLAT + MAXPSVSVCLAT stats should not be less than 1, this implies that all active and passive checks completed within negative latency! (did you supply the wrong stats file?)";
    }
}

quit $status, $msg;
