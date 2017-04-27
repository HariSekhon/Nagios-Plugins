#!/usr/bin/perl -T
# nagios: -epn
#
# Author: Hari Sekhon
# Date: 2013-06-29 23:42:18 +0100 (Sat, 29 Jun 2013)
#
# http://github.com/harisekhon
#
# License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions but referencing v3, so far everything has been available via v1
# http://cloudera.github.io/cm_api/apidocs/v3/index.html

$DESCRIPTION = "Nagios Plugin to check basic overall status of a cluster


You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all version of Cloudera Manager Enterprise Edition

";
$VERSION = "0.5";

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

my $protocol = "http";
my $api = "/api/v5";
my $default_port = 7180;
$port = $default_port;

my $cluster;
my $service;
my $list;
my $url;

my $status= 'OK';    
env_creds("CM", "Cloudera Manager");

%options = (
    %hostoptions,
    %useroptions,
    "C|cluster=s" => [ \$cluster, "Cluster Name as shown in Cloudera Manager (eg. \"Cluster - CDH4\")" ],
    "S|service=s" => [ \$service, "Service Name as shown in Cloudera Manager (eg. hdfs1, mapreduce4). Requires --cluster" ],
    "L|list" => [ \$list, "List all clusters or all serices for the supplied cluster" ],
        
);

get_options();


$host = validate_host($host);
$port = validate_port($port);
$user = validate_user($user);
$password = validate_password($password);

if(defined($cluster)){
    $cluster =~ /^\s*([\w\s\.-]+)\s*$/ or usage "Invalid cluster name given, may only contain alphanumeric, space, dash, dots or underscores";
    $cluster = $1;
    vlog_options "cluster", $cluster;
}
if(defined($service)){
    $service =~ /^\s*([\w-]+)\s*$/ or usage "Invalid service name given, must be alphanumeric with dashes";
    $service = $1;
    vlog_options "service", $service;
    $url = "$api/clusters/$cluster/services/$service";
}
if(defined($cluster) and defined($service)){
    $url = "$api/clusters/$cluster/services/$service";
}elsif(defined($cluster) and defined($list)){
    $url = "$api/clusters/$cluster/services";
}elsif(defined($list)){
    $url = "$api/clusters";
}else {
    usage "must specify on  of the following:
    --cluster --service
    --cluster --list
    --list
    ";
}
set_timeout();


$host = validate_resolvable($host);
my $url_prefix = "$protocol://$host:$port";
$url = "$url_prefix$url";




vlog2 "querying $url";
my $req = HTTP::Request->new('GET',$url);
$req->authorization_basic($user, $password);
my $response = $ua->request($req);
my $content = $response->content;
chomp $content;
vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
vlog2 "http code: " . $response->code;
vlog2 "message: " . $response->message;
if(!$response->is_success){
    my $err = "failed to query Cloudera Manager at '$url_prefix': " . $response->code . " " . $response->message;
    if($content =~ /"message"\s*:\s*"(.+)"/){
        $err .= ". Message returned by CM: $1";
    }
    if($response->message =~ /Can't verify SSL peers without knowing which Certificate Authorities to trust/){
        $err .= ". Do you need to use --ssl-CA-path or --tls-noverify?";
    }
    quit "CRITICAL", $err;
}
unless($content){
    quit "CRITICAL", "blank content returned by Cloudera Manager at '$url_prefix'";
}

vlog2 "parsing output from Cloudera Manager\n";



my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Cloudera Manager at '$url_prefix', did you try to connect to the SSL port without --tls?";
};

# Reset and store results now with or without context
my $msg = "";
if(defined($list)){
    if(defined($cluster)){
        $msg.="\nAvaliable Services for Cluster '$cluster' are\n";
        foreach(@{$json->{"items"}}){
            if(defined($_->{"name"})){
                $msg.=$_->{"name"}."\n";
            } else {
                code_error "no 'name' field returned in item from cluster service listing from Cloudera Manager at '$url_prefix', check -vvv to see the output returned by CM";
            }
        }
    }else{
	$msg.="\nAvaliable Clusters are\n";
    	foreach(@{$json->{"items"}}){
            if(defined($_->{"name"})){
        	$msg.=$_->{"name"}."\n";
	    } else {
                code_error "no 'name' field returned in item from cluster listing from Cloudera Manager at '$url_prefix', check -vvv to see the output returned by CM";
            }
        }    
    }
}else{
    my %metrics_found;
    my %metric_results;
    if(defined($json->{"healthSummary"})){
        $metrics_found{"healthSummary"} = 1;
	$metric_results{"healthSummary"}{"value"} = $json->{"healthSummary"};
    } else {
        code_error "no 'name' field returned in item from cluster service listing from Cloudera Manager at '$url_prefix', check -vvv to see the output returned by CM";
    }
    %metric_results or quit "CRITICAL", "no metrics returned by Cloudera Manager '$url_prefix', no metrics collected in last 5 mins or incorrect cluster/service/role/host for the given metric(s)?";

    foreach(sort keys %metric_results){
        my $value = $metric_results{$_}{value};
        $msg .= "$_=$value";
        # Simplified this part by not saving the unit metrics in the first place if they are not castable to Nagios PerfData units
        $msg .= $metric_results{$_}{"unit"} if defined($metric_results{$_}{"unit"});
        $msg .= " ";
        if($value ne 'GOOD'){
            $status="CRITICAL";
        }
    }
}





quit $status, $msg;