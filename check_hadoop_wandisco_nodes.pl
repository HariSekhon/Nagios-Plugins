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

# http://docs.wandisco.com/bigdata/nsnn/1.9h/api.html

$DESCRIPTION = "Nagios Plugin to check the status of all WANdisco Non-Stop Hadoop nodes via DConE REST API

Thresholds are checked against the sum of stopped and down nodes

Written and tested on Hortonworks HDP 2.1 and WANdisco Non-Stop Hadoop 1.9.8";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';
use POSIX 'floor';
use XML::Simple;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(50070);

set_threshold_defaults(0, 1);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $MAX_NODES = 5;

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/dcone/nodes";

# TODO: add 404 error handler to state WANdisco is not installed or node name is invalid
my $content = curl $url, "NameNode";

# Test sample
#my $content = '<node>
#<nodeIdentity>hdp9</nodeIdentity>
#<locationIdentity>rack5</locationIdentity>
#<isLocal>false</isLocal>
#<isUp>true</isUp>
#<isStopped>false</isStopped>
#<lastStatusChange>1394745414752</lastStatusChange>
#<attributes>
#<entry>
#<key>eco.system.membership</key>
#<value>ECO-MEMBERSHIP-cc35d900-aaf4-11e3-a3d4-0a925d65298e</value>
#</entry>
#<entry>
#<key>eco.system.dsm.identity</key>
#<value>ECO-DSM-6eb95b07-aaf4-11e3-8faf-0ec3ae3656de</value>
#</entry>
#</attributes>
#</node>';

my $xml = XMLin($content, forcearray => 0, keyattr => [] );

my @nodes = get_field2_array($xml, "node");

my $nodes = scalar @nodes;

my @stopped_nodes;
my @down_nodes;
my $nodeIdentity;

foreach my $node (@nodes){
    $nodeIdentity = get_field2($node, "nodeIdentity");
    if(get_field2($node, "isUp") ne "true"){
        push(@down_nodes, $nodeIdentity);
    }
    if(get_field2($node, "isStopped") eq "true"){
        push(@stopped_nodes, $nodeIdentity);
    }
};

my $num_stopped = scalar @stopped_nodes;
my $num_down    = scalar @down_nodes;
my $num_stopped_or_down = $num_stopped + $num_down;
my $num_up = $nodes - $num_stopped_or_down;

$msg .= "$num_up/$nodes nodes up [$num_stopped stopped, $num_down down]";
check_thresholds($num_stopped_or_down);
if($verbose){
    $msg .= "[" if(@down_nodes or @stopped_nodes);
    if(@down_nodes){
        $msg .= "down: " . join(", ", @down_nodes[0..$MAX_NODES]) . ", ";
    }
    if(@stopped_nodes){
        $msg .= "stopped: " . join(", ", @stopped_nodes[0..$MAX_NODES]) . ", ";
    }
    $msg =~ s/, $//;
    $msg .= "]" if(@down_nodes or @stopped_nodes);
}
$msg .= " | 'nodes stopped/down'=$num_stopped_or_down";
msg_perf_thresholds();
$msg .= " 'nodes stopped'=$num_stopped 'nodes down'=$num_down";

vlog2;
quit $status, $msg;
