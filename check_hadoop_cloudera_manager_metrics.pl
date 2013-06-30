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

$DESCRIPTION = "Nagios Plugin to check given Hadoop metric(s) via Cloudera Manager Rest API

http://cloudera.github.io/cm_api/apidocs/v3/index.html

It can be tricky to get the cluster/service/host/role etc qualifier for a given metric, please see the Charts section in CM";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use JSON 'decode_json';

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $default_port = 7180;
$port = $default_port;

my $activity;
my $all_metrics;
my $cluster;
my $hostid;
my $list_roles;
my $metrics;
my $nameservice;
my $role;
my $service;

my %metric_results;
my @metrics;
my %metrics_found;
my @metrics_not_found;

%options = (
    "H|host=s"         => [ \$host,         "Cloudera Manager host" ],
    "P|port=s"         => [ \$port,         "Cloudera Manager port (defaults to $default_port)" ],
    "u|user=s"         => [ \$user,         "Cloudera Manager user" ],
    "p|password=s"     => [ \$password,     "Cloudera Manager password" ],
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to fetch, comma separated (eg. dfs_capacity,dfs_capacity_used,dfs_capacity_used_non_hdfs). Thresholds may optionally be applied if a single metric is given" ],
    "a|all-metrics"    => [ \$all_metrics,  "Fetch all metrics for the given service or host etc specified by the options below. Caution, this could be a *lot* of metrics, best used to find available metrics for a given section" ],
    "C|cluster=s"      => [ \$cluster,      "Cluster Name shown in Cloudera Manager (eg. \"Cluster - CDH4\")" ],
    "S|service=s"      => [ \$service,      "Service Name shown in Cloudera Manager (eg. hdfs1, mapreduce4)" ],
    "I|hostid=s"       => [ \$hostid,       "HostId to collect metric for (eg. datanode1.domain.com)" ],
    "A|activityId=s"   => [ \$activity,     "ActivityId to collect metric for. Requires --cluster and --service" ],
    "N|nameservice=s"  => [ \$nameservice,  "Nameservice to collect metric for. Requires --cluster and --service" ],
    "R|roleID=s"       => [ \$role,         "RoleId to collect metric for (eg. hdfs4-NAMENODE-73d774cdeca832ac6a648fa305019cef - use --list-roleIds to find CM's role ids for a given service). Requires --cluster and --service" ],
    "list-roleIds"     => [ \$list_roles,   "List roleIds, convenience switch to find the above roleId, prints role ids and exits immediately. Requires --cluster and --service" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port user password metrics all-metrics cluster service hostid activity nameservice roleId list-roleIds warning critical/;
get_options();

$host       = validate_hostname($host);
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
my $url_api = "http://$user:$password\@$host:$port/api/v1";
my $url;
defined($hostid and ($cluster or $service or $activity or $nameservice or $role)) and usage "cannot specify both --hostid and --cluster/service/role type metrics at the same time";
if(defined($cluster) and defined($service)){
    $cluster    =~ /^\s*([\w\s\.-]+)\s*$/ or usage "Invalid cluster name given, may only contain alphanumeric, space, dash, dots or underscores";
    $cluster    = $1;
    $service    =~ /^\s*(\w+)\s*$/ or usage "Invalid service name given, may only be alphanumeric";
    $service    = $1;
    $url = "$url_api/clusters/$cluster/services/$service";
    if(defined($activity)){
        $activity =~ /^\s*(\w+)\s*$/ or usage "Invalid activity given, must be alphanumeric";
        $activity = $1;
        $url .= "/activities/$activity";
    } elsif(defined($nameservice)){
        $nameservice =~ /^\s*([\w-]+)\s*$/ or usage "Invalid nameservice given, must be alphanumeric";
        $nameservice = $1;
        $url .= "/nameservices/$nameservice";
    } elsif(defined($role)){
        $role =~ /^\s*([\w-]+)\s*$/ or usage "Invalid role given, must be alphanumeric";
        $role = $1;
        $url .= "/roles/$role";
    }
} elsif(defined($hostid)){
    $hostid = validate_hostname($hostid);
    $url .= "$url_api/hosts/$hostid";
} else {
    usage "must specify the type of metric to be collected using one of the following combinations:

--cluster --service
--cluster --service --activity
--cluster --service --nameservice
--cluster --service --role
--hostid
";
}
if($list_roles){
    unless(defined($cluster) and defined($service)){
        usage "must define cluster and service to be able to list roles";
    }
    $url = "$url_api/clusters/$cluster/services/$service";
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

# Doesn't work
#$ua->credentials("$host:$port", "AnyRealm", $user, $password);
$ua->show_progress(1) if $debug;
vlog2 "querying $url";
my $response = $ua->get($url);
my $content  = $response->content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message; 
if(!$response->is_success){
    my $err = "failed to query Cloudera Manager at '$host:$port': " . $response->code . " " . $response->message;
    if($content =~ /"message"\s*:\s*"(.+)"/){
        $err .= ". Message returned by CM: $1";
    }
    quit "CRITICAL", "$err";
}
unless($content){
    quit "CRITICAL", "blank content returned by Cloudera Manager at '$host:$port'";
}

vlog2 "parsing output from Cloudera Manager\n";

my $json = decode_json $content;

if($list_roles){
    my @role_list;
    foreach(@{$json->{"items"}}){
        if(defined($_->{"name"})){
            push(@role_list, $_->{"name"});
        } else {
            code_error "no 'name' field returned in item from role listing from Cloudera Manager, check -vvv to see the output returned by CM";
        }
    }
    quit "UNKNOWN", "no checks performed, roles available for cluster '$cluster', service '$service': " . join(" , ", @role_list);
}

unless(@{$json->{"items"}}){
    quit "CRITICAL", "no matching metrics returned by Cloudera Manager '$host:$port'";
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
            if($context){
                $metrics_found{$name} = 1;
                # context defined was just checked in the context check above, not re-checking here
                my $context = $_->{"context"};
                $context =~ s/$hostid:?//       if $hostid;
                $context =~ s/$cluster:?//      if $cluster;
                $context =~ s/$service:?//      if $service;
                $context =~ s/$role:?//         if $role;
                $context =~ s/$activity:?//     if $activity;
                $context =~ s/$nameservice:?//  if $nameservice;
                $name .= "_$context";
            }
            $metric_results{$name}{"value"} = $_->{"data"}[-1]{"value"};
            $metric_results{$name}{"unit"}  = $_->{"unit"} if defined($_->{"unit"});
        }
    }
}

%metric_results or quit "CRITICAL", "no metrics returned by Cloudera Manager '$host:$port', no metrics collected or incorrect cluster/service/host/role combination for the given metric(s)?";

foreach(@metrics){
    unless(defined($metrics_found{$_})){
        push(@metrics_not_found, $_);
        unknown;
    }
}

$msg = "";
foreach(sort keys %metric_results){
    $msg .= "$_=$metric_results{$_}{value}";
    if(defined($metric_results{$_}{"unit"})){
        my $units;
        if($units = isNagiosUnit($metric_results{$_}{"unit"})){
            $msg .= $units;
        }
    }
    $msg .= " ";
}
$msg =~ s/\s*$//;
if(@metrics_not_found){
    $msg = "Metrics not found: " . join(",", @metrics_not_found) . ". $msg";
}
if(scalar keys %metric_results == 1){
    check_thresholds($metric_results{$metrics[0]}{"value"});
}
$msg .= " | ";
foreach(sort keys %metric_results){
    $msg .= "$_=$metric_results{$_}{value}";
    if(defined($metric_results{$_}{"unit"})){
        my $units;
        if($units = isNagiosUnit($metric_results{$_}{"unit"})){
            $msg .= $units;
        }
    }
    $msg .= " ";
}

quit "$status", "$msg";
