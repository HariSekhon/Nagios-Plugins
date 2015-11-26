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

$DESCRIPTION = "Nagios Plugin to check % volume imported increase between the last 2 runs of specific Datameer import job using the Rest API

Use this to keep track of the amount of data imported by the latest run of a specific import job as a % increase compared to the last run that imported data. This is useful to check that you haven't changed/misconfigured something in an import job resulting in suddenly importing too much data and eating up your precious license volume since Datameer is licensed by cumulative volume of imported data.

Important Notes:

To find the JOB ID that you should supply to the --job-id option you should look at the Browser tab inside Datameer's web UI and right-click on the import job and then click Information. This will show you the JOB ID in the field \"ID: <number>\" (NOT \"File ID\")

Caveat:

1. It's possible to delete an Import Job in which case you won't be able to get this information any more since the Job no longer exists, you'll get a 404 not found error.

2. It's possible to delete one or more runs from the history of an Import Job under Administration -> Job History. Needless to say don't do this.

3. The job run history by default only goes back 28 days, so you'd need to increase this setting in conf/default.properties:

housekeeping.execution.max-age=90d

This would need to be a long enough period to retain the history for the last 2 job runs


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
my $strict;

%options = (
    %datameer_options,
    "j|job-id=s"    => [ \$job_id,      "Job Configuration Id (get this from the web UI)" ],
    "w|warning=s"   => [ \$warning,     "Warning  threshold for % increase of data imported compared to last job run (inclusive)" ],
    "c|critical=s"  => [ \$critical,    "Critical threshold for % increase of data imported compared to last job run (inclusive)" ],
    "strict"        => [ \$strict,      "Strict mode, return 'UNKNOWN' rather than 'OK' if cannot find 2 previous runs data import volumes. Use this when you know your jobs are established and importing data" ],
);

@usage_order = qw/host port user password job-id strict warning critical/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$job_id = validate_int($job_id, "job-id", 1, 100000);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 0, "positive" => 0 } );

#my $url = "http://$host:$port/rest/job-configuration/volume-report/$job_id?start=0&length=2";
# get 10 runs and try to find the last importedVolume of the last run that actually imported data
my $url = "http://$host:$port/rest/job-configuration/volume-report/$job_id";

$status = "OK";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $json = datameer_curl $url, $user, $password;

quit "UNKNOWN", "no job runs have occurred yet for job $job_id or no job history available for that job" unless @{$json};

my $job_run;
my $run_importedVolume;
sub get_importedVolume($){
    my $i = shift;
    $job_run = ${$json}[$i];
    foreach(qw/id jobStatus/){
        defined($job_run->{$_}) or quit "UNKNOWN", "job $job_id returned run result number $i field '$_' not returned by Datameer server. API format may have changed. $nagios_plugins_support_msg";
    }
    if(defined($job_run->{"importedVolume"})){
        $run_importedVolume = $job_run->{"importedVolume"};
    } else {
        $run_importedVolume = -1;
    }
    vlog2 "job: $job_id  run id: $job_run->{id}  status: $job_run->{jobStatus}  importedVolume: $run_importedVolume";
    return $run_importedVolume;
}

$run_importedVolume = get_importedVolume(0);
$run_importedVolume > 0 or quit "UNKNOWN", "latest run of job id $job_id imported no data, cannot calculate % change";

my $num_job_runs = scalar @{$json};
plural $num_job_runs;

if($num_job_runs < 2){
    if($strict){
        $status = "UNKNOWN";
    }
    quit $status, "$num_job_runs job run$plural completed, don't have last 2 runs history to compare rate of import volume change";
}

my $last_run_importedVolume = 0;
for(my $i=1; $i < $num_job_runs; $i++){
    $last_run_importedVolume = get_importedVolume($i);
    $last_run_importedVolume >= 0 and last;
}

my $pc_increase;
if($last_run_importedVolume < 1){
    if($strict){
        $status = "UNKNOWN";
    }
    plural ($num_job_runs - 1 );
    quit $status, "no data imported in the previous " . ($num_job_runs - 1) . " run$plural for job id $job_id, cannot calculate % change";
} else {
    $pc_increase = sprintf("%.2f", ($run_importedVolume - $last_run_importedVolume) / $last_run_importedVolume * 100);
}

my $human_importedVolume      = human_units($run_importedVolume);
my $human_last_importedVolume = human_units($last_run_importedVolume);

my $change = "increase";
$change = "decrease" if($pc_increase < 0);

$msg = abs($pc_increase) . "% $change between last 2 runs of job id $job_id [$human_last_importedVolume => $human_importedVolume]";
check_thresholds($pc_increase);
$msg .= " | importedVolumeIncreaseOnLast=${pc_increase}%";
msg_perf_thresholds;

vlog2;
quit $status, $msg;
