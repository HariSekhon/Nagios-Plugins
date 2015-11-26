#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-06-05 15:32:37 -0700 (Tue, 05 Jun 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to aggregate perfdata across all instances of a service check, optionally using a given host regex to only aggregate for a given cluster of hosts. Must be run on the Nagios server itself, uses the existing stats in status.dat";

$VERSION = "0.5.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $default_status_dat = "/var/log/nagios/status.dat";
my $status_dat = $default_status_dat;
my $service_desc;
my $perf_label;
my $host_regex;
my $host_regex2;
my $units;

%options = (
    "H|host-regex=s"            => [ \$host_regex2,  "Host regex to match (optional)" ],
    "s|service-description=s"   => [ \$service_desc, "Nagios service description to cluster together" ],
    "p|perf-label=s"            => [ \$perf_label,   "Perfdata label to aggregate in perfdata" ],
    "f|status-file=s"           => [ \$status_dat,   "Nagios status.dat file to check for the aggregate perfdata (defaults to $default_status_dat)" ],
    "u|units=s"                 => [ \$units,        "Units of perfdata" ],
    "w|warning=s"               => [ \$warning,      "Warning threshold or ran:ge (inclusive)"   ],
    "c|critical=s"              => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host-regex service-description perf-label status-dat warning critical/;
get_options();

if($host_regex){
    $host_regex = validate_regex($host_regex2, "host");
}
$service_desc or usage "service description not defined";
$perf_label   or usage "perfdata label not defined";
$service_desc =~ /^([\w\s_-]+)$/ or usage "invalid service description given, must be alphanumeric/whitespace";
$service_desc = $1;
$perf_label   =~ /^([\w\s_\/-]+)$/ or usage "invalid perfdata label given, must be alphanumberic/whitespace or /";
$perf_label   = $1;
vlog_option "host regex", $host_regex if $host_regex;
vlog_option "service description", $service_desc;
vlog_option "perf label", $perf_label;
$status_dat   = validate_filename($status_dat);
vlog_option "status file", $status_dat;
$units = validate_units($units) if $units;
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

my @stats;

my $hostline_regex = qr/^\s*host_name=$host_regex\s*$/o if $host_regex;

my $fh = open_file $status_dat;
my $found_host      = 0;
my $found_service   = 0;
my $found_perfdata  = 0;
my $in_service      = 0;
my $matched_host    = 0;
my $matched_service = 0;
while(<$fh>){
    $in_service = 1 if /^\s*servicestatus\s+{\s*$/;
    if($in_service){
        if($host_regex){
            $matched_host = 1 if /$hostline_regex/;
            next unless $matched_host;
            $found_host = 1;
        }
        $matched_service = 1 if /^\s*service_description=$service_desc\s*$/;
        if($matched_service){
            $found_service = 1;
            $found_perfdata = 1 if /^\s*performance_data=.+/;
            if(/^\s*performance_data=.*['"]?$perf_label['"]?=(\d+(?:\.\d+)?).*$/){
                push(@stats, $1);
            }
        }
    }
    $in_service = 0 if /^\s*}\s*$/;
    $matched_host    = 0 unless $in_service;
    $matched_service = 0 unless $in_service;
}

if($host_regex2 and not $found_host){
    quit "UNKNOWN", "No services found for host '$host_regex2', wrong hostname?";
}

quit "UNKNOWN", "No matching service '$service_desc' was found" unless $found_service;
quit "UNKNOWN", "No perfdata found for service '$service_desc'" unless $found_perfdata;

quit "UNKNOWN", "perfdata label '$perf_label' wasn't found in perfdata output (service and perfdata were found though)" unless scalar @stats;

my $average = 0;
foreach(@stats){ $average += $_ };
$average /= scalar @stats;
my $average_short =
$msg  = sprintf("%.1f", $average);
$msg .= "$units" if $units;
$msg .= " average across " . scalar @stats . " services";
check_thresholds($average_short);
$msg .= " | '$perf_label'=$average";
$msg .= "$units" if $units;
msg_perf_thresholds();
$msg .= " Services=" . scalar @stats;

quit $status, $msg;
