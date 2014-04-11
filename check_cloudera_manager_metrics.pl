#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-29 23:42:18 +0100 (Sat, 29 Jun 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check given Hadoop metric(s) via Cloudera Manager Rest API

See the Charts section in CM or --all-metrics for a given --cluster --service [--roleId] or --hostId to see what's available

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes";

$VERSION = "0.6";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $activity;
my $all_metrics;
my $list_roles;
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
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to fetch, comma separated (eg. dfs_capacity,dfs_capacity_used,dfs_capacity_used_non_hdfs). Thresholds may optionally be applied if a single metric is given" ],
    "a|all-metrics"    => [ \$all_metrics,  "Fetch all metrics for the given service/host/role specified by the options below. Caution, this could be a *lot* of metrics, best used to find available metrics for a given section" ],
    "A|activityId=s"   => [ \$activity,     "ActivityId to collect metric for. Requires --cluster and --service" ],
    "list-roleIds"     => [ \$list_roles,   "List roleIds for a given cluster service. Convenience switch to find the roleId to query, prints role ids and exits immediately. Requires --cluster and --service" ],
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

if($all_metrics){
    vlog_options "metrics", "ALL";
} elsif($list_roles){
} else {
    defined($metrics) or usage "no metrics specified";
    foreach(split(",", $metrics)){
        $_ = trim($_);
        /^\s*([\w_]+)\s*$/ or usage "invalid metric '$_' given, must be alphanumeric, may contain underscores in the middle";
        push(@metrics, $1);
    }
    @metrics or usage "no valid metrics given";
    @metrics = sort @metrics;
    vlog_options "metrics", "[ " . join(" ", @metrics) . " ]"; 
}
defined($hostid and ($cluster or $service or $activity or $nameservice or $role)) and usage "cannot specify both --hostId and --cluster/service/roleId type metrics at the same time";
if(defined($cluster) and defined($service)){
    $cluster    =~ /^\s*([\w\s\.-]+)\s*$/ or usage "Invalid cluster name given, may only contain alphanumeric, space, dash, dots or underscores";
    $cluster    = $1;
    $service    =~ /^\s*([\w-]+)\s*$/ or usage "Invalid service name given, must be alphanumeric with dashes";
    $service    = $1;
    vlog_options "cluster", $cluster;
    vlog_options "service", $service;
    $url = "$api/clusters/$cluster/services/$service";
    if(defined($activity)){
        $activity =~ /^\s*([\w-]+)\s*$/ or usage "Invalid activity given, must be alphanumeric with dashes";
        $activity = $1;
        vlog_options "activity", $activity;
        $url .= "/activities/$activity";
    } elsif(defined($nameservice)){
        $nameservice =~ /^\s*([\w-]+)\s*$/ or usage "Invalid nameservice given, must be alphanumeric with dashes";
        $nameservice = $1;
        vlog_options "nameservice", $nameservice;
        $url .= "/nameservices/$nameservice";
    } elsif(defined($role)){
        $role =~ /^\s*([\w-]+-\w+-\w+)\s*$/ or usage "Invalid role id given, expected in format such as <service>-<role>-<hexid> (eg hdfs4-NAMENODE-73d774cdeca832ac6a648fa305019cef). Use --list-roleIds to see available roles + IDs for a given cluster service";
        $role = $1;
        vlog_options "roleId", $role;
        $url .= "/roles/$role";
    }
} elsif(defined($hostid)){
    $hostid = isHostname($hostid) || usage "invalid host id given";
    vlog_options "hostId", "$hostid";
    $url .= "$api/hosts/$hostid";
} else {
    usage "must specify the type of metric to be collected using one of the following combinations:

--cluster --service
--cluster --service --activityId
--cluster --service --nameservice
--cluster --service --roleId
--hostId
";
}
if($list_roles){
    unless(defined($cluster) and defined($service)){
        usage "must define cluster and service to be able to list roles";
    }
    $url = "$api/clusters/$cluster/services/$service";
}
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";
if($list_roles){
    $url .= "/roles";
} else {
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
}

cm_query();

if($list_roles){
    my @role_list;
    foreach(@{$json->{"items"}}){
        if(defined($_->{"name"})){
            push(@role_list, $_->{"name"});
        } else {
            code_error "no 'name' field returned in item from role listing from Cloudera Manager at '$url_prefix', check -vvv to see the output returned by CM";
        }
    }
    usage "no checks performed, roles available for cluster '$cluster', service '$service':\n\n" . join("\n", @role_list);
}

unless(@{$json->{"items"}}){
    quit "CRITICAL", "no matching metrics returned by Cloudera Manager '$url_prefix'";
}

# Pre-populate to check for context requirements
my $context = 0;
my %metrics_contexts;
foreach(@{$json->{"items"}}){
    foreach my $field (qw/name data/){
        defined($_->{$field}) or quit "UNKNOWN", "no '$field' field returned item collection from Cloudera Manager, run with -vvv to see the (malformed?) json returned";
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
