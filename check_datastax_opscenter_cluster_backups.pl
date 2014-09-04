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

Also checks durable writes are enabled by default, configurable to expect durable writes to be disabled instead.

Tested on DataStax OpsCenter 5.0.0";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8888);

env_creds("DataStax OpsCenter");

my $cluster;
my $list_clusters;

%options = (
    %hostoptions,
    %useroptions,
    "C|cluster=s"    =>  [ \$cluster,        "Cluster as named in DataStax OpsCenter. See --list-clusters" ],
    "K|keyspace=s"   =>  [ \$keyspace,       "KeySpace to check. See --list-keyspaces" ],
    "list-clusters"  =>  [ \$list_clusters,  "List clusters managed by DataStax OpsCenter" ],
    "list-keyspaces" =>  [ \$list_keyspaces, "List keyspaces in given Cassandra cluster managed by DataStax OpsCenter. Requires --cluster" ],
);
splice @usage_order, 6, 0, qw/cluster keyspace list-clusters list-keyspaces/;

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
} elsif($keyspace) {
    $url = "http://$host:$port/$cluster/backups/$keyspace";
} else {
    $url = "http://$host:$port/$cluster/backups";
}

$json = curl_json $url, "DataStax OpsCenter", $user, $password;
vlog3 Dumper($json);

if($list_clusters){
    print "Clusters managed by DataStax OpsCenter:\n\n";
    foreach(sort keys %{$json}){
        print "$_\n";
    }
    exit $ERRORS{"UNKNOWN"};
}

vlog2;
quit $status, $msg;
