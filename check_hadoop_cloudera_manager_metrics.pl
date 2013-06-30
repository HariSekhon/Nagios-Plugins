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

$VERSION = "0.1";

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
my $cluster;
my $hostid;
my $metrics;
my $nameservice;
my $role;
my $service;

%options = (
    "H|host=s"         => [ \$host,         "Cloudera Manager host" ],
    "P|port=s"         => [ \$port,         "Cloudera Manager port (defaults to $default_port)" ],
    "u|user=s"         => [ \$user,         "Cloudera Manager user" ],
    "p|password=s"     => [ \$password,     "Cloudera Manager password" ],
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to fetch, comma separated (eg. dfs_capacity_used,dfs_capacity_used_non_hdfs). Thresholds may optionally be applied if a single metric is given" ],
    "C|cluster=s"      => [ \$cluster,      "Cluster Name shown in Cloudera Manager (eg. \"Cluster - CDH4\")" ],
    "S|service=s"      => [ \$service,      "Service Name shown in Cloudera Manager (eg. hdfs1, mapreduce4)" ],
    "I|hostid=s"       => [ \$hostid,       "HostId to collect metric for (eg. datanode1.domain.com)" ],
    "A|activity=s"     => [ \$activity,     "ActivityId to collect metric for (eg. MapReduce). Requires --cluster and --service" ],
    "N|nameservice=s"  => [ \$nameservice,  "Nameservice to collect metric for. Requires --cluster and --service" ],
    "R|role=s"         => [ \$role,         "RoleName to collect metric for. Requires --cluster and --service" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold or ran:ge (inclusive)" ],
);

@usage_order = qw/host port user password metrics cluster service hostid activity nameservice role warning critical/;
get_options();

$host       = validate_hostname($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
defined($metrics) or usage "no metrics specified";
my @metrics;
foreach(split(",", $metrics)){
    $_ = trim($_);
    /^\s*([\w_]+)\s*$/ or usage "invalid metric '$_' given, must be alphanumeric, may contain underscores in the middle";
    push(@metrics, $1);
}
@metrics or usage "no valid metrics given";
my $url = "http://$user:$password\@$host:$port/api/v1";
if(defined($cluster) and defined($service)){
    $cluster    =~ /^\s*([\w\s\.-]+)\s*$/ or usage "Invalid cluster name given, may only contain alphanumeric, space, dash, dots or underscores";
    $cluster    = $1;
    $service    =~ /^\s*(\w+)\s*$/ or usage "Invalid service name given, may only be alphanumeric";
    $service    = $1;
    $url .= "/clusters/$cluster/services/$service";
    if(defined($activity)){
        $activity =~ /^(\w+)$/ or usage "Invalid activity given, must be alphanumeric";
        $activity = $1;
        $url .= "/activities/$activity";
    } elsif(defined($nameservice)){
        $nameservice =~ /^[\w-]+$/ or usage "Invalid nameservice given, must be alphanumeric";
        $nameservice = $1;
        $url .= "/nameservices/$nameservice";
    } elsif(defined($role)){
        $role =~ /^[\w-]+$/ or usage "Invalid role given, must be alphanumeric";
        $role = $1;
        $url .= "/roles/$role";
    }
} elsif(defined($hostid)){
    $hostid = validate_hostname($hostid);
    $url .= "/hosts/$hostid";
} else {
    usage "must specify the type of metric to be collected using one of the following combinations:

--cluster --service
--cluster --service --activity
--cluster --service --nameservice
--cluster --service --role
--hostid
";
}
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";
$url .= "/metrics?";
foreach(@metrics){
    $url .= "metrics=$_&";
}
$url =~ s/\&$//;

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

unless(@{$json->{"items"}}){
    quit "CRITICAL", "no matching metrics returned by Cloudera Manager '$host:$port'";
}

my %metric_results;
foreach(@{$json->{"items"}}){
    if(defined($_->{"data"}[4]{"value"})){
        $metric_results{$_->{"name"}}{"value"} = $_->{"data"}[4]{"value"};
        $metric_results{$_->{"name"}}{"unit"}  = $_->{"unit"} if defined($_->{"unit"});
    }
}

%metric_results or quit "CRITICAL", "no metrics returned by Cloudera Manager '$host:$port', no metrics collected or incorrect cluster/service/host/role combination for the given metric(s)?";

my @metrics_not_found;
foreach(@metrics){
    unless(defined($metric_results{$_})){
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
    $msg .= ". Metrics not found: " . join(",", @metrics_not_found);
}
if(scalar @metrics == 1){
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
