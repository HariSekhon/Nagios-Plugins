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

To find the JOB ID that you should supply to the --job-id option you should look at the Browser tab inside Datameer's web UI and right-click on the import job and then click Information. This will show you the JOB ID in the field \"ID: <number>\" (NOT \"File ID\")

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

my $url = "http://$host:$port/rest/job-configuration/job-history/$job_id?start=0&length=1";

vlog2;
set_timeout();
set_http_timeout(($timeout - 1) / 2);

my $json = datameer_curl $url, $user, $password;

quit "UNKNOWN", "no job runs have occurred yet for job $job_id or no job history available for that job" unless @{$json};

my $job_run = @{$json}[0];

defined($job_run->{"id"}) or quit "UNKNOWN", "job run id not returned by Datameer server for latest run of job $job_id";
isInt($job_run->{"id"}) or quit "UNKNOWN", "non-integer returned for latest job run id by Datameer server (got '$$job_run->{id}')";

$url = "http://$host:$port/rest/job-execution/job-details/$job_run->{id}";

$job_run = datameer_curl $url, $user, $password;

foreach(qw/jobStatus failureCount successCount counters startTime stopTime/){
    defined($job_run->{$_}) or quit "UNKNOWN", "job $job_id '$_' field not returned by Datameer server";
}
foreach(qw/failureCount successCount/){
    isInt($job_run->{$_})   or quit "UNKNOWN", "job $job_id '$_' returned non-integer '$job_run->{$_}', investigation required";
}
foreach(qw/IMPORT_RECORDS IMPORT_BYTES IMPORT_DROPPED_RECORDS IMPORT_PREVIEW_RECORDS IMPORT_OUTPUT_BYTES IMPORT_DROPPED_SPLITS IMPORT_OUTPUT_PARTITIONS/){
    defined($job_run->{"counters"}->{$_}) or $job_run->{"counters"}->{$_} = 0;
    isInt(  $job_run->{"counters"}->{$_}) or quit "UNKNOWN", "job $job_id counter '$_' returned non-integer '$job_run->{counters}->{$_}', investigation required";
}

my $job_status = $job_run->{"jobStatus"};

$status = "UNKNOWN";
foreach my $state (qw/CRITICAL WARNING OK/){
    if(grep($job_status eq $_, @{$datameer_job_state{$state}})){
        $status = $state;
        last;
    }
}

$msg = sprintf("job %d state '%s', failureCount %s, successCount %s, last start time '%s', stop time '%s' |", $job_id, lc $job_status, $job_run->{"failureCount"}, $job_run->{"successCount"}, $job_run->{"startTime"}, $job_run->{"stopTime"});
foreach(qw/IMPORT_RECORDS IMPORT_BYTES IMPORT_DROPPED_RECORDS IMPORT_PREVIEW_RECORDS IMPORT_OUTPUT_BYTES IMPORT_DROPPED_SPLITS IMPORT_OUTPUT_PARTITIONS/){
    $msg .= sprintf(" %s=%d", lc $_, $job_run->{"counters"}->{$_});
}

quit $status, $msg;
