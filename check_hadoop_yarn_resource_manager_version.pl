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

$DESCRIPTION = "Nagios Plugin to check the version of a Hadoop Yarn Resource Manager via REST API

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385) and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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

my $expected;

%options = (
    %hostoptions,
    "e|expected=s" => [ \$expected, "Expected version (regex, optional)" ],
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
$expected = validate_regex($expected) if defined($expected);

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

my $rm_version = get_field("clusterInfo.resourceManagerVersion");

$msg = "yarn resource manager version: $rm_version";
check_regex($rm_version, $expected) if defined($expected);

quit $status, $msg;
