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

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the volume of imported data for specific Datameer job using the Rest API

Use this to keep track of the amount of data imported by each job since Datameer is licensed by volume of imported data

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
    "j|job-id=s"    => [ \$job_id,      "Job Configuration Id (get this from the web UI)" ],
    "w|warning=s"   => [ \$warning,     "Warning threshold (inclusive)" ],
    "w|critical=s"  => [ \$critical,    "Critical threshold (inclusive)" ],
);

@usage_order = qw/host port user password job-id/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
$job_id = validate_int($job_id, "job-id", 1, 100000);
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

my $url = "http://$host:$port/rest/job-configuration/volume-report/$job_id";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $json = datameer_curl $url, $user, $password;

foreach(qw/id importedVolume/){
    defined($json->{$_}) or quit "UNKNOWN", "job $job_id not found on Datameer server";
}

$json->{"id"} == $job_id or quit "CRITICAL", "datameer server returned wrong job id!!";

my $job_imported_volume = $json->{"importedVolume"};

$msg .= "job $job_id imported volume " . human_units($job_imported_volume) . " [$job_imported_volume ";
check_thresholds($job_imported_volume);
$msg .= "] | importedVolume=${job_imported_volume}b";
msg_perf_thresholds;

quit $status, $msg;
