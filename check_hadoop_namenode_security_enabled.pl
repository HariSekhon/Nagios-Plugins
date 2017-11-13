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

$DESCRIPTION = "Nagios Plugin to check if a Hadoop NameNode has Security Enabled via JMX API

Tested on Hortonworks HDP 2.1 (Hadoop 2.4.0) and Apache Hadoop 2.3, 2.4, 2.5, 2.6, 2.7, 2.8";

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
%options = (
    %hostoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/jmx?qry=Hadoop:service=NameNode,name=NameNodeStatus";

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
my $security_enabled;
foreach(@beans){
    next unless get_field2($_, "name") eq "Hadoop:service=NameNode,name=NameNodeStatus";
    $found_mbean = 1;
    $security_enabled = get_field2($_, "SecurityEnabled");
    last;
}
quit "UNKNOWN", "failed to find namenode status mbean" unless $found_mbean;

$msg = sprintf("namenode security enabled '%s'", ($security_enabled ? "true" : "false"));
critical unless $security_enabled;

quit $status, $msg;
