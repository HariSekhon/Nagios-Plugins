#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-03-05 21:45:08 +0000 (Wed, 05 Mar 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the state of the Hadoop Yarn Resource Manager via REST API

Tip: run this against a load balancer in front of your Resource Managers or in conjunction with find_active_hadoop_yarn_resource_manager.py to check that you always have an active master available

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385) and Apache Hadoop 2.5.2, 2.6.4, 2.7.2";

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

set_port_default(8088);

env_creds(["HADOOP_YARN_RESOURCE_MANAGER", "HADOOP"], "Yarn Resource Manager");

%options = (
    %hostoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/ws/v1/cluster";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by Yarn Resource Manager at '$url'";
};
vlog3(Dumper($json));

my $state      = get_field("clusterInfo.state");
my $started    = get_field("clusterInfo.startedOn");
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
