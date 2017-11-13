#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-08 18:34:41 +0000 (Fri, 08 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check if a Hadoop NameNode is in Safe Mode via JMX

Raises warning status if the NameNode is in Safe Mode.

Tested on Hortonworks HDP 2.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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

set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

%options = (
    %hostoptions,
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo";

$json = curl_json $url;

my @beans = get_field_array("beans");

my $found_mbean = 0;
my $Safemode;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=NameNodeInfo";
    $found_mbean = 1;
    $Safemode = get_field2($_, "Safemode");
    last;
}
unless($found_mbean){
    quit "UNKNOWN", "failed to find NameNodeInfo mbean. $nagios_plugins_support_msg_api" unless $found_mbean;
}

warning if $Safemode;
$Safemode = ( $Safemode ? "true" : "false");

$msg = "NameNode safe mode = $Safemode";

quit $status, $msg;
