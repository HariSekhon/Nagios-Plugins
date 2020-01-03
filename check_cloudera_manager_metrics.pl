#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-29 23:42:18 +0100 (Sat, 29 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check given Hadoop metric(s) via Cloudera Manager Rest API

See the Charts section in CM or --all-metrics for a given --cluster --service [--roleId] or --hostId to see what's available

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

Requires CM API <= v5 since v6 onwards changed the metrics API to the timeseries API so this doesn't support Cloudera Manager 6+

Tested on Cloudera Manager 4.5, 4.6, 5.0.0, 5.7.0, 5.10.0, 5.12.0";

$VERSION = "0.8.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $all_metrics;
my $metrics;
my %metric_results;
my %metrics_found;
my @metrics;
my @metrics_not_found;

%options = (
    %hostoptions,
    %useroptions,
    %thresholdoptions,
    %cm_options,
    %cm_options_list,
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to fetch, comma separated (eg. dfs_capacity,dfs_capacity_used,dfs_capacity_used_non_hdfs). Thresholds may optionally be applied if a single metric is given" ],
    "a|all-metrics"    => [ \$all_metrics,  "Fetch all metrics for the given service/host/role specified by the options below. Caution, this could be a *lot* of metrics, best used to find available metrics for a given section" ],
    "A|activityId=s"   => [ \$activity,     "ActivityId to collect metric for. Requires --cluster and --service" ],
);

get_options();

$api        = "/api/v5";

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

validate_cm_cluster_options();

if($all_metrics){
    vlog_option "metrics", "ALL";
} elsif(listing_cm_components()){
} else {
    defined($metrics) or usage "no metrics specified";
    foreach(split(",", $metrics)){
        $_ = trim($_);
        /^\s*([\w_]+)\s*$/ or usage "invalid metric '$_' given, must be alphanumeric, may contain underscores in the middle";
        push(@metrics, $1);
    }
    @metrics or usage "no valid metrics given";
    @metrics = uniq_array @metrics;
    vlog_option "metrics", "[ " . join(" ", @metrics) . " ]";
}

validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

list_cm_components();

$url .= "/metrics?";
if($debug){
    $url .= "view=full&"
}
if(not $all_metrics){
    foreach(@metrics){
        $url .= "metrics=$_&";
    }
    $url =~ s/\&$//;
}
$url =~ s/\?$//;

cm_query();

unless(@{$json->{"items"}}){
    quit "CRITICAL", "no matching metrics returned by Cloudera Manager '$url_prefix'";
}

# Pre-populate to check for context requirements
my $context = 0;
my %metrics_contexts;
foreach(@{$json->{"items"}}){
    foreach my $field (qw/name data/){
        defined($_->{$field}) or quit "UNKNOWN", "no '$field' field returned item collection from Cloudera Manager. $nagios_plugins_support_msg_api";
    }
    if(defined($_->{"data"}[-1])){
        if(defined($metric_results{$_->{"name"}})){
            defined($_->{"context"}) or quit "UNKNOWN", "logic error, found name '$_->{name}' twice but no context field, unsure how to differentiate!";
            $context = 1;
        }
        $metric_results{$_->{"name"}} = 1;
    }
}

# Reset and store results now with or without context
%metric_results = ();
foreach(@{$json->{"items"}}){
    # 5 results are usually returned already sorted in chronological order so just take the latest one
    if(defined($_->{"data"}[-1])){
        if(defined($_->{"data"}[-1]{"value"})){
            my $name = $_->{"name"};
            $metrics_found{$name} = 1;
            if($context){
                # context defined was just checked in the context check above, not re-checking here
                my $context = $_->{"context"};
                $context =~ s/$hostid:?//       if $hostid;
                $context =~ s/$cluster:?//      if $cluster;
                $context =~ s/$service:?//      if $service;
                $context =~ s/$role:?//         if $role;
                $context =~ s/$activity:?//     if $activity;
                $context =~ s/$nameservice:?//  if $nameservice;
                $name .= "_$context" if $context;
            }
            $metric_results{$name}{"value"} = $_->{"data"}[-1]{"value"};
            if(defined($_->{"unit"})){
                # isNagiosUnit returns undef if not castable to official Nagios PerfData units
                $metric_results{$name}{"unit"} = isNagiosUnit($_->{"unit"});
            }
            if($verbose >= 2){
                printf "%-20s \t%-20s \tvalue: %-12s", $_->{"name"}, $name, $metric_results{$name}{"value"};
                if(defined($_->{"unit"})){
                    printf " \tunit: %-10s \tunit castable to Nagios PerfData: ", $_->{unit};
                    print defined($metric_results{$name}{"unit"}) ? "yes" : "no";
                }
                print "\n";
            }
        }
    }
}
vlog2;

%metric_results or quit "CRITICAL", "no metrics returned by Cloudera Manager '$url_prefix', no metrics collected in last 5 mins or incorrect cluster/service/role/host for the given metric(s)?";

foreach(@metrics){
    unless(defined($metrics_found{$_})){
        push(@metrics_not_found, $_);
        unknown;
    }
}

$msg = "";
foreach(sort keys %metric_results){
    $msg .= "$_=$metric_results{$_}{value}";
    # Simplified this part by not saving the unit metrics in the first place if they are not castable to Nagios PerfData units
    $msg .= $metric_results{$_}{"unit"} if defined($metric_results{$_}{"unit"});
#    if(defined($metric_results{$_}{"unit"})){
#        my $units;
#        if($units = isNagiosUnit($metric_results{$_}{"unit"})){
#            $msg .= $units;
#        }
#    }
    $msg .= " ";
}
$msg =~ s/\s*$//;
if(@metrics_not_found){
    $msg = "Metrics not found: " . join(",", @metrics_not_found) . ". $msg";
}
# TODO: extend library to support simultaneous multi metric thresholding, non-trivial to do, requires significant code and design decisions
# For now will only check upper bound for highest metric if a single metric yields multiple contextual metrics such as host write_ios per partition
if(scalar @metrics == 1){
    if(scalar keys %metric_results > 1){
        my $highest_metric = 0;
        foreach(sort keys %metric_results){
            $highest_metric = $metric_results{$_}{"value"} if $metric_results{$_}{"value"} > $highest_metric;
        }
        check_thresholds($highest_metric);
    } else {
        check_thresholds($metric_results{$metrics[0]}{"value"});
    }
}
$msg .= " | ";
foreach(sort keys %metric_results){
    $msg .= "$_=$metric_results{$_}{value}";
    # Simplified this part by not saving the unit metrics in the first place if they are not castable to Nagios PerfData units
    $msg .= $metric_results{$_}{"unit"} if defined($metric_results{$_}{"unit"});
#    if(defined($metric_results{$_}{"unit"})){
#        my $units;
#        if($units = isNagiosUnit($metric_results{$_}{"unit"})){
#            $msg .= $units;
#        }
#    }
    $msg .= " ";
}

quit $status, $msg;
