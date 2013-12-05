#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 22:56:19 +0000 (Thu, 05 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS30/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the status of a specific Datameer job using the Rest API and output details of job success and failure counts as well as the following counters in perfdata for graphing:

import_records
import_bytes
import_dropped_records
import_preview_records
import_output_bytes
import_dropped_splits
import_output_partitions

Tested against Datameer 3.0.11";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Datameer;
use JSON::XS;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname $main::VERSION");

my $job_id;

%options = (
    %datameer_options,
    "j|job-id=s"       => [ \$job_id,       "Job Configuration Id (get this from the web UI)" ],
);

@usage_order = qw/host port user password job-id/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$job_id = validate_int($job_id, "job-id", 1, 100000);

my $url = "http://$host:$port/rest/job-execution/job-details/$job_id";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

#my $json = datameer_curl $url, $user, $password;

$json = {
    "counters" => {
        "IMPORT_RECORDS" => 494400,
        "IMPORT_BYTES" => 23911522,
        "IMPORT_DROPPED_RECORDS" => 0,
        "IMPORT_PREVIEW_RECORDS" => 5000,
        "IMPORT_OUTPUT_BYTES" => 24444883,
        "IMPORT_DROPPED_SPLITS" => 0,
        "IMPORT_OUTPUT_PARTITIONS" => 0
    },
    "failureCount" => 0,
    "jobStatus" => "COMPLETED",
    "startTime" => "2012-07-06 18:19:09.0",
    "stopTime" => "2012-07-06 18:21:07.0",
    "successCount" => 494400
};

foreach(qw/jobStatus failureCount successCount counters startTime stopTime/){
    defined($json->{$_}) or quit "UNKNOWN", "job $job_id '$_' field not returned by Datameer server";
}
foreach(qw/failureCount successCount/){
    isInt($json->{$_})   or quit "UNKNOWN", "job $job_id '$_' returned non-integer '$json->{$_}', investigation required";
}
foreach(qw/IMPORT_RECORDS IMPORT_BYTES IMPORT_DROPPED_RECORDS IMPORT_PREVIEW_RECORDS IMPORT_OUTPUT_BYTES IMPORT_DROPPED_SPLITS IMPORT_OUTPUT_PARTITIONS/){
    defined($json->{$_}) or quit "UNKNOWN", "job $job_id counter '$_' not returned by Datameer server";
    isInt($json->{$_})   or quit "UNKNOWN", "job $job_id counter '$_' returned non-integer '$json->{$_}', investigation required";
}

my $job_status = $json->{"jobStatus"};

$status = "UNKNOWN";
foreach my $state (qw/CRITICAL WARNING OK/){
    if(grep($job_status eq $_, @{$datameer_job_state{$state}})){
        $status = $state;
        last;
    }
}

$msg = sprintf("job %d state '%s', failureCount %s, successCount %s, start time '%s', stop time '%s' |", $job_id, lc $job_status, $json->{"failureCount"}, $json->{"successCount"}, $json->{"startTime"}, $json->{"stopTime"});
foreach(qw/IMPORT_RECORDS IMPORT_BYTES IMPORT_DROPPED_RECORDS IMPORT_PREVIEW_RECORDS IMPORT_OUTPUT_BYTES IMPORT_DROPPED_SPLITS IMPORT_OUTPUT_PARTITIONS/){
    $msg .= sprintf(" %s=%d", lc $_, $json->{$_});
}

quit $status, $msg;
