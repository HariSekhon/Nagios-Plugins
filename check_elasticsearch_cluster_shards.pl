#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-06-03 21:43:25 +0100 (Mon, 03 Jun 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the numbers of different types of Elasticsearch cluster shards and especially to check for unassigned shards

Thresholds apply to counts of active primary shards, active shards, relocating shards, initializing shards and unassigned shards in <warning>,<critical> format where each threshold can take a standard Nagios ra:nge

Tested on Elasticsearch 0.90, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 2.0, 2.1, 2.2, 2.3, 2.4, 5.0, 5.1, 5.2, 5.3, 5.4, 5.5, 5.6, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6";

$VERSION = "0.4.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Elasticsearch;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $cluster;
my $active_primary_shard_thresholds;
my $active_shard_thresholds;
my $relocating_shard_thresholds = "0,0:";
my $initializing_shard_thresholds = "0,0:";
my $unassigned_shard_thresholds = "0,1";

%options = (
    %hostoptions,
    %useroptions,
    %ssloptions,
    "C|cluster-name=s"          =>  [ \$cluster,                            "Cluster name to expect (optional). Cluster name is used for auto-discovery and should be unique to each cluster in a single network" ],
    "active-primary-shards=s"   =>  [ \$active_primary_shard_thresholds,    "Active Primary Shards lower thresholds (inclusive, optional)" ],
    "active-shards=s"           =>  [ \$active_shard_thresholds,            "Active Shards lower thresholds (inclusive, optional)" ],
    "relocating-shards=s"       =>  [ \$relocating_shard_thresholds,        "Relocating Shards upper thresholds (inclusive, default w,c: 0,0:)" ],
    "initializing-shards=s"     =>  [ \$initializing_shard_thresholds,      "Initializing Shards upper thresholds (inclusive, default w,c: 0,0:)" ],
    "unassigned-shards=s"       =>  [ \$unassigned_shard_thresholds,        "Unassigned Shards upper thresholds (inclusive, default w,c: 0,1)" ],
);
splice @usage_order, 6, 0, qw/cluster-name active-primary-shards active-shards relocating-shards initializing-shards unassigned-shards/;

get_options();

$host = validate_host($host);
$port = validate_port($port);
if($password){
    $user = validate_user($user);
    $password = validate_password($password);
}
$cluster = validate_elasticsearch_cluster($cluster) if defined($cluster);
my $options_upper = { "simple" => "upper", "integer" => 1, "positive" => 1 };
my $options_lower = { "simple" => "lower", "integer" => 1, "positive" => 1 };
validate_thresholds(undef, undef, $options_lower, "active primary shards",  $active_primary_shard_thresholds);
validate_thresholds(undef, undef, $options_lower, "active shards",          $active_shard_thresholds);
validate_thresholds(undef, undef, $options_upper, "relocating shards",      $relocating_shard_thresholds);
validate_thresholds(undef, undef, $options_upper, "initializing shards",    $initializing_shard_thresholds);
validate_thresholds(undef,     1, $options_upper, "unassigned shards",      $unassigned_shard_thresholds);

vlog2;
set_timeout();

$status = "OK";

$json = curl_elasticsearch "/_cluster/health";

my $cluster_name = get_field("cluster_name");
$msg .= "cluster name: '$cluster_name'";
check_string($cluster_name, $cluster);

my $msg2 = "";

my $active_primary_shards = get_field_int("active_primary_shards");
$msg .= ", active primary shards: $active_primary_shards";
check_thresholds($active_primary_shards, 0, "active primary shards");
$msg2 .= " 'active primary shards'=$active_primary_shards" . msg_perf_thresholds(1, 1, "active primary shards");

my $active_shards = get_field_int("active_shards");
$msg .= ", active shards: $active_shards";
check_thresholds($active_shards, 0, "active shards");
$msg2 .= " 'active shards'=$active_shards" . msg_perf_thresholds(1, 1, "active shards");

my $relocating_shards = get_field_int("relocating_shards");
$msg .= ", relocating shards: $relocating_shards";
check_thresholds($relocating_shards, 0, "relocating shards");
$msg2 .= " 'relocating shards'=$relocating_shards" . msg_perf_thresholds(1, 0, "relocating shards");

my $initializing_shards = get_field_int("initializing_shards");
$msg .= ", inititializing shards: $initializing_shards";
check_thresholds($initializing_shards, 0, "initializing shards");
$msg2 .= " 'initializing shards'=$initializing_shards" . msg_perf_thresholds(1, 0, "initializing shards");

my $unassigned_shards = get_field_int("unassigned_shards");
$msg .= ", unassigned shards: $unassigned_shards";
check_thresholds($unassigned_shards, 0, "unassigned shards");
$msg2 .= " 'unassigned shards'=$unassigned_shards" . msg_perf_thresholds(1, 0, "unassigned shards");

my $timed_out = get_field("timed_out");
#$timed_out = ( $timed_out ? "true" : "false" );
if($timed_out){
    critical;
    $msg .= ", TIMED OUT: TRUE";
    #check_string($timed_out, "false");
}

$msg .= " |$msg2";

vlog2;
quit $status, $msg;
