#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the state of the Hadoop Yarn Resource Manager via REST API

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385)";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");
$ua->requests_redirectable([]);

set_port_default(8088);

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Yarn Resource Manager");

%options = (
    %hostoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster";

sub error_handler($) {
	my $response = shift;

	open my $tmpfile, ">","/tmp/protocoll_check_hadoop_yarn_resource_manager_state";
        print $tmpfile Dumper $response;
        print $tmpfile "response code: ", $response->code ,"\n";
        close $tmpfile;



        if($response->code eq "307"){
            my $active = $response->header("Location");
            quit("OK", "Standby RM, active at $active");
        }
        unless($response->code eq "200"){
            my $additional_information = "";
            my $json;
            if($json = isJson($response->content)){
                if(defined($json->{"status"})){
                    $additional_information .= ". Status: " . $json->{"status"};
                }
                if(defined($json->{"reason"})){
                    $additional_information .= ". Reason: " . $json->{"reason"};
                } elsif(defined($json->{"message"})){
                    $additional_information .= ". Message: " . $json->{"message"};
                }
            }
            quit("CRITICAL", $response->code . " " . $response->message . $additional_information);
        }
        unless($response->content){
            quit("CRITICAL", "blank content returned from '" . $response->request->uri . "'");
        }
}

my $content = curl $url, undef, undef, undef, \&error_handler;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my $state          = get_field("clusterInfo.state");
my $started        = get_field("clusterInfo.startedOn");
my $rm_version = get_field("clusterInfo.resourceManagerVersion");

$started = localtime($started / 1000);

# NOTINITED, INITED, STARTED, STOPPED
if($state eq "STARTED"){
    # ok
} elsif($state eq "INITED" or $state eq "NOTINITED"){
    warning;
} else {
    # STOPPED
    critical;
}

$msg = "yarn resource manager state: $state, started on: $started, version: $rm_version";

quit $status, $msg;
