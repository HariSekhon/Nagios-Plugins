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

$DESCRIPTION = "Nagios Plugin to check if a Hadoop NameNode is the Active/Standby one in an HA pair via JMX

Written and tested on Hortonworks HDP 2.1 (Hadoop 2.4.0.2.1.1.0-385). Added legacy support for Cloudera CDH 4.4.0 (Hadoop 2.0.0)";

$VERSION = "0.2";

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

set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $active;
my $standby;
my $expected_state;

%options = (
    %hostoptions,
    "active"        => [ \$active,  "Expect Active  (optional)" ],
    "standby"       => [ \$standby, "Expect Standby (optional)" ],
);
splice @usage_order, 6, 0, qw/active standby/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$active and $standby and usage "cannot specify both --active and --standby they are mutually exclusive!";
if($active){
    $expected_state = "active";
} elsif($standby){
    $expected_state = "standby";
}

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx";

my $content = curl $url;

try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by NameNode at '$url'";
};
vlog3(Dumper($json));

my @beans = get_field_array("beans");

my $found_mbean = 0;
my $state;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=NameNodeStatus";
    $found_mbean = 1;
    $state = get_field2($_, "State");
    last;
}
unless($found_mbean){
    foreach(@beans){
        # This is to be able to support CDH 4.4 which doesn't have the NameNodeStatus MBean
        next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=FSNamesystem";
        $found_mbean = 1;
        $state = get_field2($_, 'tag\.HAState');
        last;
    }
    quit "UNKNOWN", "failed to find namenode status mbean. $nagios_plugins_support_msg_api" unless $found_mbean;
}

$msg = "namenode state '$state'";
if($expected_state){
    critical if($expected_state ne $state);
    if($verbose or $expected_state ne $state){
        $msg .= " (expected: '$expected_state')";
    }
}

quit $status, $msg;
