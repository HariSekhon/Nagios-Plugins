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

$DESCRIPTION = "Nagios Plugin to check jobs and failed jobs on an 0xdata H2O machine learning cluster via REST API

Warning and Critical thresholds are applied to the number of failed jobs, by default any failed jobs trigger CRITICAL

Tested on 0xdata H2O 2.2.1.3, 2.4.3.4, 2.6.1.5

TODO: H2O 3.x API has changed, updates required
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

set_threshold_defaults(0, 0);

env_creds("H2O");

%options = (
    %hostoptions,
    %thresholdoptions,
);
@usage_order = qw/host port warning critical/;

get_options();

$host        = validate_host($host);
$port        = validate_port($port);
validate_thresholds(1, 1, { "simple" => "upper", "positive" => 1, "integer" => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url_prefix = "http://$host:$port";
my $url = "$url_prefix/Jobs.json";

my $content = curl $url;

my $json;
try{
    $json = decode_json $content;
};
catch{
    quit "invalid json returned by H2O at '$url_prefix'";
};
vlog3(Dumper($json));

defined($json->{"jobs"}) or quit "UNKNOWN", "'jobs' field not returned by H2O at '$url_prefix'. $nagios_plugins_support_msg_api";

isArray($json->{"jobs"}) or quit "UNKNOWN", "'jobs' field is not an array as expected. $nagios_plugins_support_msg_api";

my %failed_jobs;
foreach my $job (@{$json->{"jobs"}}){
    defined($job->{"description"})     or quit "UNKNOWN", "'description' field not found. $nagios_plugins_support_msg_api";
    defined($job->{"result"}->{"val"}) or quit "UNKNOWN", "job result not found for job '" . $job->{"description"} . "'. $nagios_plugins_support_msg_api";
    $job->{"result"}->{"val"} eq "OK"  or $failed_jobs{$job->{"description"}} = 1;
}

my $job_count        = scalar(@{$json->{"jobs"}});
my $job_failed_count = scalar(keys %failed_jobs);
if($job_failed_count > $job_count){
    critical;
    $msg .= "job failed count > job count!! ";
}
$msg .= "$job_count jobs, $job_failed_count failed jobs";
check_thresholds($job_failed_count);

if(%failed_jobs){
    critical;
    if($verbose){
        $msg .= " (failed jobs: ";
        foreach(sort keys %failed_jobs){
            $msg .= "$_, ";
        }
        $msg =~ s/, $/)/;
    }
}

$msg .= " | jobs=$job_count failed_jobs=$job_failed_count";
msg_perf_thresholds();

vlog2;
quit $status, $msg;
