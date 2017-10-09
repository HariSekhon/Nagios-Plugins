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

$DESCRIPTION = "Nagios Plugin to check the status of a given WANdisco Non-Stop Hadoop node via DConE REST API

Checks node state is up, not stopped, and displays the secs since the last status change.

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

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $node;

%options = (
    %hostoptions,
    "N|node=s"  =>  [ \$node,   "Node to check (must match the WANdisco node name precisely or will get a 404 not found error)" ],
);

get_options();

$host = validate_host($host);
$port = validate_port($port);
# In WANdisco nodes can be called things that wouldn't pass FQDN / IP address tests
usage "node not defined" unless $node;
#$node = validate_host($node, "node");

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/dcone/node/$node";

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

my $nodeIdentity        = get_field2($xml, "nodeIdentity");
my $locationIdentity    = get_field2($xml, "locationIdentity");
my $isLocal             = get_field2($xml, "isLocal");
my $isUp                = get_field2($xml, "isUp");
my $isStopped           = get_field2($xml, "isStopped");
my $lastStatusChange    = get_field2_float($xml, "lastStatusChange");

$isUp      = ( $isUp and $isUp eq "true" ? "true" : "FALSE" );
$isStopped = ( $isStopped and $isStopped ne "false" ? "TRUE" : "false" );
$isLocal   = ( $isLocal and $isLocal eq "true" ? "true" : "false" );
# TODO: add quorum field

if ($isStopped eq "true" or $isUp ne "true"){
    critical;
}

my $last_status_change = floor(time - ($lastStatusChange / 1000));
# TODO: move to library and polish up
my $human_time;
if($last_status_change > 86400){
    $human_time = sprintf("%.1f days", $last_status_change / 86400);
} elsif($last_status_change > 3600){
    $human_time = sprintf("%.1f hours", $last_status_change / 3600);
} else {
    $human_time = "$last_status_change secs";
}

$msg .= "node '$nodeIdentity' location '$locationIdentity' up='$isUp' stopped='$isStopped' local='$isLocal' last status change = $human_time ago ($last_status_change secs)";
if($last_status_change < 0){
    warning;
    $msg .= " (in future, NTP issue?)";
}

vlog2;
quit $status, $msg;
