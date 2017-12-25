#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check the MapR license on a MapR Hadoop cluster via the MapR Control System REST API

Checks time left on license in days against configurable warning/critical thresholds

Raises warning on trial license unless setting --trial-ok

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.2.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::MapR;
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(31, 15);

my $trial_ok = 0;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    "trial-ok"     =>  [ \$trial_ok, "Suppress warning if Trial license" ],
    "w|warning=s"  =>  [ \$warning,  "Warning  threshold in days (default: $default_warning)"  ],
    "c|critical=s" =>  [ \$critical, "Critical threshold in days (default: $default_critical)" ],
);
splice @usage_order, 10, 0, 'trial-ok';

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
validate_thresholds(1, 1, { "simple" => "lower", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/license/list";
$url .= "?cluster=$cluster" if $cluster;
$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

foreach(@data){
    my $desc = get_field2($_, "description");
    debug "description: $desc";
    next if($desc =~ /MapR Base Edition|Base MapR POSIX Client/);
    unless($trial_ok){
        warning if $desc =~ /trial|evaluation/i;
    }
    #$msg .= "version: "    . get_field2($_, "license") . ", ";
    my $expiry;
    #if(defined($_->{"expiry"})){
        $expiry = get_field2($_, "expiry");
        $expiry =~ /^(\w+)\s+(\d{1,2}),\s*(\d{4})$/ or quit "UNKNOWN", "expiry is not in the expected format. $nagios_plugins_support_msg_api";
    #} elsif(defined($_->{"expdateStr"})){
    #    $expiry = get_field2($_, "expdateStr");
    #    $expiry =~ /^\w{3} (\w{3}) (\d{2}) .+ (\d{4})\s*$/ or quit "UNKNOWN", "expdateStr is not in the expected format. $nagios_plugins_support_msg_api";
    #} else {
    #    quit "UNKNOWN", "neither 'expiry' nor expdateStr fields found. $nagios_plugins_support_msg_api";
    #}
    my $month = month2int($1);
    my $day   = $2;
    my $year  = $3;
    my $days_left = floor(timecomponents2days($year, $month, $day, 0, 0, 0));
    if($days_left < 0){
        $msg = "$desc license EXPIRED " . abs($days_left) . " days ago";
    } else {
        $msg .= "$desc license expires in $days_left days";
    }
    check_thresholds($days_left);
    $msg .= ", expiry: '$expiry', ";
    $msg .= "issued: '"     . get_field2($_, "issue", "noquit") . "', ";
    $msg .= "max nodes: "  . get_field2($_, "maxnodes") . ", ";
}
$msg =~ s/, $//;

vlog2;
quit $status, $msg;
