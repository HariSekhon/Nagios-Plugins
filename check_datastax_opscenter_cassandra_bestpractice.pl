#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-09-15 23:11:32 +0100 (Mon, 15 Sep 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/best_practice.html

$DESCRIPTION = "Nagios Plugin to check DataStax OpsCenter best practice rule results for a given cluster via the DataStax OpsCenter Rest API

By default shows the last run status of all rules and raises critical if any of them are not of status='Passed'.

Can specify an individual --rule (as displayed by the default mode that shows them all) and then optionally have that rule --run immediately instead of using the last run result. Specifying a rule also provides additional output for that one rule of 'category', 'importance', 'scope' and 'last_run_time' as well as the recommendation of how to correct it if status does not equal 'Passed'.

Requires DataStax Enterprise 5.0.0 onwards

Tested on DataStax OpsCenter 5.0.0";

$VERSION = "0.2";

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
my $run;

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    "R|rule=s"     => [ \$rule,   "Best practive rule to run. Optional, defaults to showing the last run results for all rules" ],
    "run"          => [ \$run,    "Run given --rule and report result instead of using last run results. Only valid when specifying a single --rule" ],
);
splice @usage_order, 6, 0, qw/cluster rule run list-clusters/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
if($run and not $rule){
    usage "cannot specify --run without --rule";
}
if($rule){
    $rule =~ /^([\w-]+)$/ or usage "invalid --check argument, must be alphanumeric with dashes or underscores";
    $rule = $1;
    vlog_option "rule", $rule;
}
vlog_option "run now", ( $run ? "true" : "false");

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();

if($rule and $run){
    $json = curl_opscenter "$cluster/bestpractice/run/$rule", 0, "POST";
} else {
    $json = curl_opscenter "$cluster/bestpractice/results/latest";
}
vlog3 Dumper($json);

isHash($json) or quit "UKNOWN", "non-hash returned by DataStax OpsCenter";

my $result_status;
my $Passed = "Passed";

sub check_result(;$){
    my $prefix = shift || "";
    $prefix .= "." if $prefix;
    $result_status = get_field("${prefix}status");
    $msg .= "$rule='$result_status'";
    if($result_status ne $Passed){
        critical;
        $msg .= " display-name='"    . get_field("${prefix}display-name")   . "'"
              . ", recommendation='" . get_field("${prefix}recommendation") . "'";
    }
    $msg .= ", category='"      . get_field("${prefix}category")   . "'"
          . ", importance='"    . get_field("${prefix}importance") . "'"
          . ", scope='"         . get_field("${prefix}scope")      . "'"
          . ", last_run_time='" . get_field("${prefix}run_time")   . "'";
}

if($rule and $run){
    check_result();
} elsif($rule){
    defined($json->{$rule}) or quit "UNKNOWN", "rule '$rule' not found, check you have specified a valid run name by running without --rule first to see all the rules";
    check_result($rule);
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
