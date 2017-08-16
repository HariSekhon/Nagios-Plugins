#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-15 23:13:13 +0100 (Mon, 15 Sep 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/hadoop.html

$DESCRIPTION = "Nagios Plugin to check Hadoop status for a DataStax Enterprise Analytics Cluster via DataStax OpsCenter's Rest API

Optional thresholds apply to the minimum number of active tasktrackers. Raises critical if service state does not equal 1 (running) or there are blacklisted tasktrackers or excluded nodes detected

Requires DataStax Enterprise and only valid when run against a DataStax Enterprise Analytics Cluster being managed by DataStax OpsCenter

Tested on DataStax OpsCenter 5.0.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use Data::Dumper;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
validate_thresholds(0, 0, { "simple" => "lower", "integer" => 1, "positive" => 1});


vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

sub curl_opscenter_err_handler_analytics($){
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
                if($json->{"message"} eq "'NoneType' object has no attribute 'cluster_status'"){
                    $additional_information = ". Can only run this against an Analytics cluster of DataStax Enterprise. If multiple clusters are being managed by DataStax OpsCenter check that you have specified the right --cluster, see --list-clusters output to check the cluster names";
                }
            }
        }
        quit("CRITICAL", $response->code . " " . $response->message . $additional_information);
    }
    if($content =~ /^null$/i) {
        quit "UNKNOWN", $response->code. " ". $response->message . " - 'null' returned by DataStax OpsCenter - invalid parameter or combination of parameters?";
    }
    unless($content){
        quit("CRITICAL", "blank content returned from DataStax OpsCenter");
    }
};

$json = curl_json "http://$host:$port/$cluster/hadoop/status", "DataStax OpsCenter", $user, $password, \&curl_opscenter_err_handler_analytics;
vlog3 Dumper($json);

my $state                    = get_field_int("state");
my $num_active_trackers      = get_field_int("num_active_trackers");
my $num_blacklisted_trackers = get_field_int("num_blacklisted_trackers");
my $num_excluded_nodes       = get_field_int("num_excluded_nodes");

# I'm guessing here since it's not documented what state = 1 actually means
if($state == 1){
    $state = "running";
} else {
    $state = "STOPPED";
}

critical if($state ne "running" or $num_blacklisted_trackers or $num_excluded_nodes);

plural $num_active_trackers;
$msg = "state = '$state', $num_active_trackers active tracker$plural";
check_thresholds($num_active_trackers);
plural $num_blacklisted_trackers;
$msg .= ", $num_blacklisted_trackers blacklisted tracker$plural";
plural $num_excluded_nodes;
$msg .= ", $num_excluded_nodes excluded node$plural | 'active trackers'=$num_active_trackers";
msg_perf_thresholds();
$msg .= " 'blacklisted trackers'=$num_blacklisted_trackers 'excluded nodes'=$num_excluded_nodes";

quit $status, $msg;
