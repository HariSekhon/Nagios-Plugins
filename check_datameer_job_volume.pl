#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-05 23:16:51 +0000 (Thu, 05 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS30/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the culumative volume of data imported by a specific Datameer job using the Rest API

Use this to keep track of the amount of data imported by each job cumulatively for all runs of that job since Datameer is licensed by cumulative volume of imported data. This allows you to compare different jobs and see what they are costing you for comparison with the global volume license (see check_datameer_license_volume.pl for the global license volume used)

Tested against Datameer 3.0.11";

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

$ua->agent("Hari Sekhon $progname $main::VERSION");

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

quit "UNKNOWN", "no job runs have occurred yet for job $job_id or no job history available for that job or it is not an Import Job id (Data Link and Workbook IDs return no job runs)" unless @{$json};

my $i = 0;
my $job_run;
my $run_importedVolume;
my $job_imported_volume = 0;
foreach $job_run (@{$json}){
    $i++;
    foreach(qw/id jobStatus/){
        defined($job_run->{$_})  or quit "UNKNOWN", "job $job_id returned run result number $i field '$_' not returned by Datameer server. API format may have changed. $nagios_plugins_support_msg";
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
