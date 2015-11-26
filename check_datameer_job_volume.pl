#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 23:16:51 +0000 (Thu, 05 Dec 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS30/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the cumulative volume of data imported by a specific Datameer job using the Rest API

Use this to keep track of the amount of data imported by each job cumulatively for all runs of that job since Datameer is licensed by cumulative volume of imported data. This allows you to compare different jobs and see what they are costing you for comparison with the global volume license (see check_datameer_license_volume.pl for the global license volume used)

Important Notes:

To find the JOB ID that you should supply to the --job-id option you should look at the Browser tab inside Datameer's web UI and right-click on the import job and then click Information. This will show you the JOB ID in the field \"ID: <number>\" (NOT \"File ID\")

It's possible to supply a Workbook ID, Data Link ID or Export Job ID and the API happily returns the runs with no imported volume information since there was no data imported. This results in 0 bytes imported being reported, which is technically accurate, it doesn't count against the Datameer licensed volume.

Caveat:

1. It's possible to delete an Import Job in which case you won't be able to get this information any more since the Job no longer exists, you'll get a 404 not found error.

2. It's possible to delete one or more runs from the history of an Import Job under Administration -> Job History. This would reduce the job's cumulative runs imported volume result, which is based on this history. Needless to say you should not do this. Datameer will retain the correct 'License total size' on the Browser page next to the job regardless, which would show the true number so you could see such a discrepancy.

3. The job run history by default only goes back 28 days, so you'd need to increase this setting in conf/default.properties:

housekeeping.execution.max-age=365d

Although you'd have to increase this to your licensing period and it still wouldn't be exact since I'd have to add start date calculation to only iterate on job runs from a given date to count against the current licensing period. Currently talking to the Datameer guys to figure out if there is a better way to do this by exposing the internal calculation that Datameer keeps which looks like isn't exposed via API right now

Tested against Datameer 3.0.11 and 3.1.1";

$VERSION = "0.3";

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
    "j|job-id=s"    => [ \$job_id,      "Job Configuration Id (get this from the web UI)" ],
    "w|warning=s"   => [ \$warning,     "Warning threshold (inclusive)" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold (inclusive)" ],
);

@usage_order = qw/host port user password job-id/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$job_id = validate_int($job_id, "job-id", 1, 100000);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

my $url = "http://$host:$port/rest/job-configuration/volume-report/$job_id";

$status = "OK";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $json = datameer_curl $url, $user, $password;

quit "UNKNOWN", "no job runs have occurred yet for job $job_id or no job history available for that job" unless @{$json};

my $i = 0;
my $job_run;
my $run_importedVolume;
my $job_imported_volume = 0;
foreach $job_run (@{$json}){
    $i++;
    foreach(qw/id jobStatus/){
        defined($job_run->{$_}) or quit "UNKNOWN", "job $job_id returned run result number $i field '$_' not returned by Datameer server. API format may have changed. $nagios_plugins_support_msg";
    }
    if(defined($job_run->{"importedVolume"})){
        $run_importedVolume = $job_run->{"importedVolume"};
    } else {
        $run_importedVolume = 0;
    }
    vlog2 "job: $job_id  run id: $job_run->{id}  status: $job_run->{jobStatus}  importedVolume: $run_importedVolume";
    $job_imported_volume += $run_importedVolume;
}

my $human_output = human_units($job_imported_volume);
if($human_output !~ "bytes"){
    $human_output .= " [$job_imported_volume bytes]";
}
my $num_runs = scalar @{$json};
$msg .= "job $job_id cumulative imported volume across $num_runs runs is $human_output";
check_thresholds($job_imported_volume);
$msg .= " | importedVolume=${job_imported_volume}B";
msg_perf_thresholds;

vlog2;
quit $status, $msg;
