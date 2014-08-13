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

set_port_default(50070);

env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");

my $active;
my $standby;
my $expected_state;
my $release = "hortonworks";

my %release_vendor = (
'hortonworks' => {
    'tag'       => 'State',
    'bean'      => "Hadoop:service=NameNode,name=NameNodeStatus",
    'split_tag' => 1,
},
'cloudera4' => {
    'tag'       => 'tag.HAState',
    'bean'      => 'Hadoop:service=NameNode,name=FSNamesystem',
    'split_tag' => 0,
}
);

%options = (
%hostoptions,
"active"        => [ \$active,  "Expect Active  (optional)" ],
"standby"       => [ \$standby, "Expect Standby (optional)" ],
"release|r=s"   => [ \$release, "Hadoop Release"],
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

if (not exists $release_vendor{$release}) {
    usage "you set --release to $release; --release must be one of: " . join(" ", sort keys %release_vendor);
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
    next unless get_field2($_, "name") eq $release_vendor{$release}{"bean"};
    $found_mbean = 1;
    $state = get_field2($_, $release_vendor{$release}{"tag"}, $release_vendor{$release}{split_tags});
    last;
}
quit "UNKNOWN", "failed to find namenode status mbean" unless $found_mbean;

$msg = "namenode state '$state'";
if($expected_state){
    critical if($expected_state ne $state);
    if($verbose or $expected_state ne $state){
        $msg .= " (expected: '$expected_state')";
    }
}

quit $status, $msg;
