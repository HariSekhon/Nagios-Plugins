#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-27 20:07:10 +0000 (Wed, 27 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://documentation.datameer.com/documentation/display/DAS21/Accessing+Datameer+Using+the+REST+API

$DESCRIPTION = "Nagios Plugin to check the status of a specific Datameer job using the Rest API

Tested against Datameer 2.1.4.6, 3.0.11 and 3.1.1";

$VERSION = "0.3.1";

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

my $url = "http://$host:$port/rest/job-configuration/job-status/$job_id";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

my $json = datameer_curl $url, $user, $password;

defined($json->{"id"}) or quit "UNKNOWN", "job $job_id not found on Datameer server";
defined($json->{"jobStatus"}) or quit "UNKNOWN", "job $job_id field 'jobStatus' not returned by Datameer server. API format may have changed. $nagios_plugins_support_msg";

# the returned ID is actually last job run id not job id, cannot compare
#$json->{"id"} == $job_id or quit "CRITICAL", "datameer server returned wrong job id!!";

my $job_status = $json->{"jobStatus"};

$status = "UNKNOWN";
foreach my $state (qw/CRITICAL WARNING OK/){
    if(grep($job_status eq $_, @{$datameer_job_state{$state}})){
        $status = $state;
        last;
    }
}

$msg = "job $job_id state '" . lc $job_status . "'";

quit $status, $msg;
