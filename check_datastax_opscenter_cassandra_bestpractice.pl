#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-15 23:11:32 +0100 (Mon, 15 Sep 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/best_practice.html

$DESCRIPTION = "Nagios Plugin to check DataStax OpsCenter best practice rule results for a given cluster via the DataStax OpsCenter Rest API

By default shows the last run status of all rules and raises critical if any of them are not of status='Passed'.

Specify an individual --rule as displayed by the default mode that shows them all to have that rule run immediately instead of using the last run result. Provides additional output for that one rule of 'category', 'importance' and 'scope' as well as the recommendation to correct it if status does not equal 'Passed'.

Requires DataStax Enterprise

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

my $rule;

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    "R|rule=s"     => [ \$rule,   "Best practive rule to run. Optional, defaults to showing the last run results for all rules" ],
);
splice @usage_order, 6, 0, qw/cluster rule list-clusters/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
if($rule){
    $rule =~ /^([\w-]+)$/ or usage "invalid --check argument, must be alphanumeric with dashes or underscores";
    $rule = $1;
    vlog_options "rule", $rule;
}

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

if($rule){
    $json = curl_opscenter "$cluster/bestpractice/run/$rule", 0, "POST";
} else {
    $json = curl_opscenter "$cluster/bestpractice/results/latest";
}
vlog3 Dumper($json);

isHash($json) or quit "UKNOWN", "non-hash returned by DataStax OpsCenter";

my $result_status;
my $Passed = "Passed";
if($rule){
    $result_status = get_field("status");
    $msg = "$rule='$result_status'";
    if($result_status ne $Passed){
        critical;
        $msg .= " display-name='"    . get_field("display-name")   . "'"
              . ", recommendation='" . get_field("recommendation") . "'";
    }
    $msg .= ", category='"   . get_field("category")   . "'"
          . ", importance='" . get_field("importance") . "'"
          . ", scope='"      . get_field("scope")      . "'";
} else {
    my @passed;
    my %failed;
    foreach (sort keys %{$json}){
        $result_status = get_field("$_.status");
        if($result_status eq $Passed){
            push(@passed, $_);
        } else {
            $failed{$_} = $result_status;
        }
    }
    if(%failed){
        critical;
        foreach(sort keys %failed){
            $msg .= "$_=$failed{$_}, ";
        }
    }
    foreach(@passed){
        $msg .= "$_='$Passed', ";
    }
    $msg =~ s/, $//;
}

vlog2;
quit $status, $msg;
