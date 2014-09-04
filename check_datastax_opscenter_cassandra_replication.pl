#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/data_modeling.html#method-get-keyspaces

$DESCRIPTION = "Nagios Plugin to check Cassandra's replication factor and replica placement strategy for a given cluster and keyspace via the DataStax OpsCenter Rest API

Tested on DataStax OpsCenter 5.0.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8888);

env_creds("DataStax OpsCenter");

my $cluster;
my $keyspace;
my $expected_replication_factor;
my $expected_replication_strategy;
my $list_clusters;
my $list_keyspaces;

%options = (
    %hostoptions,
    %useroptions,
    "C|cluster=s"               =>  [ \$cluster,                        "Cluster as named in DataStax OpsCenter. See --list-clusters" ],
    "K|keyspace=s"              =>  [ \$keyspace,                       "KeySpace to check. See --list-keyspaces" ],
    "F|replication-factor=s"    =>  [ \$expected_replication_factor,    "Replication factor to expect (integer, optional)" ],
    "S|replication-strategy=s"  =>  [ \$expected_replication_strategy,  "Replication strategy to expect (string of class name eg. 'org.apache.cassandra.locator.SimpleStrategy', optional)" ],
    "list-clusters"             =>  [ \$list_clusters,                  "List clusters managed by DataStax OpsCenter" ],
    "list-keyspaces"            =>  [ \$list_keyspaces,                 "List keyspaces in given Cassandra cluster managed by DataStax OpsCenter. Requires --cluster" ],
);
splice @usage_order, 6, 0, qw/cluster keyspace replication-factor replication-strategy list-clusters list-keyspaces/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
unless($list_clusters){
    $cluster or usage "must specify cluster, use --list-clusters to show clusters managed by DataStax OpsCenter";
    $cluster = validate_alnum($cluster, "cluster name");
    unless($list_keyspaces){
        $keyspace or usage "must specify keyspace, use --list-keyspaces to show keyspaces managed by Cassandra cluster '$cluster'";
        $keyspace = validate_alnum($keyspace, "keyspace name");
    }
}
$expected_replication_factor = validate_int($expected_replication_factor, "expected replication factor", 1) if defined($expected_replication_factor);

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $url;
if($list_clusters){
    $url = "http://$host:$port/cluster-configs";
} elsif($list_keyspaces){
    $url = "http://$host:$port/$cluster/keyspaces";
} else {
    $url = "http://$host:$port/$cluster/keyspaces/$keyspace";
}

sub curl_datastax_opscenter_err_handler($){
    my $response = shift;
    my $content  = $response->content;
    my $json;
    my $additional_information = "";
    unless($response->code eq "200"){
        my $additional_information = "";
        my $json;
        if($json = isJson($content)){
            if(defined($json->{"status"})){
                $additional_information .= ". Status: " . $json->{"status"};
            }
            if(defined($json->{"reason"})){
                $additional_information .= ". Reason: " . $json->{"reason"};
            } elsif(defined($json->{"message"})){
                $additional_information .= ". Message: " . $json->{"message"};
                if($json->{"message"} eq "Resource not found."){
                    $additional_information = ". Message: keyspace not found - wrong keyspace specified? (case sensitive)";
                }
            }
        }
        quit("CRITICAL", $response->code . " " . $response->message . $additional_information);
    }
    unless($content){
        quit("CRITICAL", "blank content returned from DataStax OpsCenter");
    }
}

$json = curl_json $url, "DataStax OpsCenter", $user, $password, \&curl_datastax_opscenter_err_handler;

if($list_clusters){
    print "Clusters managed by DataStax OpsCenter:\n\n";
    foreach(sort keys %{$json}){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}
if($list_keyspaces){
    print "Keyspaces in cluster '$cluster':\n\n";
    foreach(sort keys %{$json}){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

my $replica_placement_strategy = get_field("replica_placement_strategy");
my $replication_factor         = get_field_int("strategy_options.replication_factor");

$msg = "cluster '$cluster' keyspace '$keyspace' replication factor: '$replication_factor'";
if(defined($expected_replication_factor) and $replication_factor != $expected_replication_factor){
    critical;
    $msg .= " (expected: $expected_replication_factor)";
}

$msg .= ", strategy: '$replica_placement_strategy'";
if(defined($expected_replication_strategy) and $replica_placement_strategy ne $expected_replication_strategy){
    critical;
    $msg .= " (expected: $expected_replication_strategy)";
}

vlog2;
quit $status, $msg;
