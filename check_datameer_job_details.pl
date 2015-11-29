#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 22:56:19 +0000 (Thu, 05 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS30/Accessing+Datameer+Using+the+REST+API

my @import_job_counters = qw/IMPORT_RECORDS IMPORT_DROPPED_RECORDS IMPORT_PREVIEW_RECORDS IMPORT_BYTES IMPORT_OUTPUT_BYTES IMPORT_DROPPED_SPLITS IMPORT_OUTPUT_PARTITIONS/;
my @export_job_counters = qw/EXPORT_RECORDS EXPORT_DROPPED_RECORDS EXPORT_BYTES/;

$DESCRIPTION = "Nagios Plugin to check the status of a specific Datameer job using the Rest API and output details of job success and failure counts as well as counters for the last job run as perfdata for graphing.

Detects whether job is an import or export job and outputs the following relevant counters as perfdata:

" . lc(join("\n", @import_job_counters))  . "

OR

" . lc(join("\n", @export_job_counters)) . "

To find the JOB ID that you should supply to the --job-id option you should look at the Browser tab inside Datameer's web UI and right-click on the import job and then click Information. This will show you the JOB ID in the field \"ID: <number>\" (NOT \"File ID\")

Tested against Datameer 3.0.11 and 3.1.1";

$VERSION = "0.5.1";

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

$ua->agent("Hari Sekhon $progname version $main::VERSION");

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

# ============================================================================ #
sub isExportJob($){
    my $job_run = shift;
    foreach(@export_job_counters){
        defined($job_run->{"counters"}->{$_}) and return 1;
    }
    return 0;
}
sub isImportJob($){
    my $job_run = shift;
    foreach(@import_job_counters){
        defined($job_run->{"counters"}->{$_}) and return 1;
    }
    return 0;
}
# ============================================================================ #

my $import_job = 0;
my $export_job = 0;

if(isExportJob($job_run)){
    vlog2 "detected export job\n";
    $export_job = 1;
} elsif(isImportJob($job_run)){
    vlog2 "detected import job\n";
    $import_job = 1;
} elsif (defined($job_run->{"counters"}) and defined($job_run->{"jobStatus"}) and $job_run->{"jobStatus"} eq "ERROR"){
    my $err_msg = sprintf("job %d state: '%s'", $job_id, $job_run->{"jobStatus"});
    if(defined($job_run->{"startTime"})){
        $err_msg .= sprintf(", last start time '%s'", $job_run->{"startTime"});
    }
    if(defined($job_run->{"stopTime"})){
        $err_msg .= sprintf(", stop time '%s'", $job_run->{"stopTime"});
    }
    quit "CRITICAL", $err_msg;
} else {
    quit "UNKNOWN", "only import and export jobs are supported (job id specified returned last run details with none of the expected counters for either type of job)";
}

foreach(qw/jobStatus failureCount successCount counters startTime stopTime/){
    defined($job_run->{$_}) or quit "UNKNOWN", "job $job_id '$_' field not returned by Datameer server";
}
foreach(qw/failureCount successCount/){
    isInt($job_run->{$_})   or quit "UNKNOWN", "job $job_id '$_' returned non-integer '$job_run->{$_}', investigation required";
}

if($import_job){
    foreach(@import_job_counters){
        defined($job_run->{"counters"}->{$_}) or $job_run->{"counters"}->{$_} = 0;
        isInt(  $job_run->{"counters"}->{$_}) or quit "UNKNOWN", "job $job_id counter '$_' returned non-integer '$job_run->{counters}->{$_}', investigation required";
    }
} elsif($export_job){
    foreach(@export_job_counters){
        defined($job_run->{"counters"}->{$_}) or $job_run->{"counters"}->{$_} = 0;
        isInt(  $job_run->{"counters"}->{$_}) or quit "UNKNOWN", "job $job_id counter '$_' returned non-integer '$job_run->{counters}->{$_}', investigation required";
    }
} else {
    code_error "could not determine if this is an import or an export job. $nagios_plugins_support_msg";
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
if($import_job){
    foreach(@import_job_counters){
        $msg .= sprintf(" %s=%d", lc $_, $job_run->{"counters"}->{$_});
    }
} elsif($export_job){
    foreach(@export_job_counters){
        $msg .= sprintf(" %s=%d", lc $_, $job_run->{"counters"}->{$_});
    }
} else {
    code_error "could not determine if this is an import or an export job late in processing! $nagios_plugins_support_msg";
}

quit $status, $msg;
