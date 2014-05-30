#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-05 22:03:20 +0100 (Sat, 05 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given node's health in an 0xdata H2O machine learning cluster via REST API

The node is the same one given to the --host switch (auto-determines H2O's node name for the node you connected to)

Technically the cluster should dissolve if a node fails but this is an additional check on node health possibly pre-empting failure
";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use JSON;
use LWP::UserAgent;

our $ua = LWP::UserAgent->new;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(54321);

env_creds("H2O");

my $list_nodes;

%options = (
    %hostoptions,
    "list-nodes"        => [ \$list_nodes,  "List nodes in H2O cluster and exit" ],
);
@usage_order = qw/host port list-nodes warning critical/;

get_options();

$host        = validate_host($host);
$port        = validate_port($port);

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/Cloud.json";

my $content = curl $url;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by H2O at '$url_prefix'";
};
vlog3(Dumper($json));

foreach(qw/node_name nodes/){
    defined($json->{$_}) or usage "field '$_' not defined in output returned from H2O. $nagios_plugins_support_msg_api";
}

isArray($json->{"nodes"}) or quit "UNKNOWN" , "'nodes' field is not an array as expected. $nagios_plugins_support_msg_api";

if($list_nodes){
    print "H2O cluster nodes:\n\n";
    foreach my $node (@{$json->{"nodes"}}){
        defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
        print $node->{"name"} . "\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $found_node = 0;
my $health;
foreach my $node (@{$json->{"nodes"}}){
    defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
    if($node->{"name"} eq $json->{"node_name"}){
        $found_node = 1;
        $health = ( $node->{"node_healthy"} ? "true" : "false" );
        last;
    }
}
$found_node or quit "UNKNOWN", "failed to find node. $nagios_plugins_support_msg_api";

$msg .= "node ";
$msg .= sprintf("'%s' ", $json->{"node_name"}) if $verbose;
$msg .= sprintf("healthy: %s", $health);
critical unless $health eq "true";

vlog2;
quit $status, $msg;
