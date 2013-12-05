#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the status of a specific Datameer job using the Rest API

Tested against Datameer 2.1.4.6 and 3.0.11";

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

my $url = "http://$host:$port/rest/job-configuration/job-status/$job_id";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $json = datameer_curl $url, $user, $password;

foreach(qw/id jobStatus/){
    defined($json->{$_}) or quit "UNKNOWN", "job $job_id not found on Datameer server";
}

$json->{"id"} == $job_id or quit "CRITICAL", "datameer server returned wrong job id!!";

my $job_status = $json->{"jobStatus"};

my %job_state;
$job_state{"OK"}       = [qw/RUNNING WAITING_FOR_OTHER_JOB COMPLETED QUEUED/];
$job_state{"WARNING"}  = [qw/COMPLETED_WITH_Warnings CANCELED CANCELLED/];
$job_state{"CRITICAL"} = [qw/ERROR/];

$status = "UNKNOWN";
foreach my $state (qw/CRITICAL WARNING OK/){
    if(grep($job_status eq $_, @{$job_state{$state}})){
        $status = $state;
        last;
    }
}

$msg = "job $job_id state '" . lc $job_status . "'";

quit $status, $msg;
