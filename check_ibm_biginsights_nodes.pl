#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights Nodes via the BigInsights Console REST API

Checks:

- dead nodes vs thresholds (default: w=0, c=1)
- outputs perfdata of live and dead nodes

Tested on IBM BigInsights Console 2.1.2.0";

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

set_port_default(8080);
set_threshold_defaults(0, 1);

env_creds("BIGINSIGHTS", "IBM BigInsights Console");

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $api = "data/controller";

our $protocol = "http";

my $skip_operational_check;

%options = (
    %hostoptions,
    %useroptions,
    %tlsoptions,
    %thresholdoptions,
);
@usage_order = qw/host port user password tls ssl-CA-path tls-noverify warning critical/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds();

tls_options();

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

my $url = "$url_prefix/$api/ClusterStatus/cluster_summary.json";

my $content = curl $url, "IBM BigInsights Console", $user, $password;
my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by IBM BigInsights Console at '$url_prefix'. Try with -vvv to see full output";
};
vlog3(Dumper($json));

$json->{"items"} or quit "UNKNOWN", "'items' field not found in json output. $nagios_plugins_support_msg_api";
my $nodes;
isArray($json->{"items"}) or quit "UNKNOWN", "'items' field is not an array as expected. $nagios_plugins_support_msg_api";
foreach my $item (@{$json->{"items"}}){
    defined($item->{"id"}) or quit "UNKNOWN", "'id' field not found in json output. $nagios_plugins_support_msg_api";
    if($item->{"id"} eq "nodes"){
        $nodes = $item;
    }
}
defined($nodes) or quit "UNKNOWN", "couldn't find 'nodes' item in json returned by BigInsights Console. $nagios_plugins_support_msg_api";
foreach(qw/live dead/){
    defined($nodes->{$_}) or quit "UNKNOWN", "'$_' field not found in nodes output. $nagios_plugins_support_msg_api";
    isInt($nodes->{$_})   or quit "UNKNOWN", "'$_' field was not an integer as expected (returned: " . $nodes->{$_} . ")! $nagios_plugins_support_msg_api";
}
$msg .= "BigInsights ";
foreach(qw/live dead/){
    $msg .= sprintf("%s nodes = %s, ", $_, $nodes->{$_});
}
$msg =~ s/, $//;
vlog2 "checking dead nodes against thresholds";
check_thresholds($nodes->{"dead"});
$msg .= sprintf(" | 'live nodes'=%d 'dead nodes'=%d", $nodes->{"live"}, $nodes->{"dead"});
msg_perf_thresholds();

vlog2;
quit $status, $msg;
