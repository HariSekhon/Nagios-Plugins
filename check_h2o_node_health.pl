#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-05 22:03:20 +0100 (Sat, 05 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given node's health in an 0xdata H2O machine learning cluster via REST API

The node is the same one given to the --host switch (auto-determines H2O's node name for the node you connected to). Optionally you can specify a different node to check using the --node switch. Use --list-nodes to see the valid H2O node names

Technically the cluster should dissolve if a node fails but this is an additional check on node health possibly pre-empting failure

Tested on 0xdata H2O 2.2.1.3, 2.4.3.4, 2.6.1.5

TODO: H2O 3.x API has changed, updates required
";

$VERSION = "0.2";

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
my $node_name;

%options = (
    %hostoptions,
    "n|node=s"          => [ \$node_name,   "Node to check the health for. Optional, will check the health of the node you connect to if no explicit node is specified" ],
    "list-nodes"        => [ \$list_nodes,  "List nodes in H2O cluster and exit" ],
);
@usage_order = qw/host port node list-nodes/;

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
my $node_name2 = $json->{"node_name"};
$node_name2 = $node_name if defined($node_name);
foreach my $node (@{$json->{"nodes"}}){
    defined($node->{"name"}) or quit "UNKNOWN", "'name' field not defined for node. $nagios_plugins_support_msg_api";
    if($node->{"name"} eq $node_name2){
        $found_node = 1;
        defined($node->{"node_healthy"}) or quit "UNKNOWN", sprintf("'node_healthy' field not defined for node '%s'. %s", $node_name2, $nagios_plugins_support_msg_api);
        $health = ( $node->{"node_healthy"} ? "true" : "false" );
        last;
    }
}
unless($found_node){
    my $node_err = "failed to find node health";
    $node_err .= sprintf(" for node '%s'. Did you specify the correct node? Use --list-nodes to check the H2O node names", $node_name) if defined($node_name);
    $node_err .= ". $nagios_plugins_support_msg_api";
    quit "UNKNOWN", $node_err;
}

$msg .= "node ";
$msg .= sprintf("'%s' ", $node_name2) if $verbose;
$msg .= sprintf("healthy: %s", $health);
critical unless $health eq "true";

vlog2;
quit $status, $msg;
