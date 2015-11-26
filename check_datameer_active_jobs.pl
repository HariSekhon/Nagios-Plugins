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

$DESCRIPTION = "Nagios Plugin to check the number of active Datameer jobs using the Datameer Rest API

Tested against Datameer 2.1.4.6, 3.0.11 and 3.1.1";

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

%options = (
    %datameer_options,
    "w|warning=s"      => [ \$warning,      "Warning  threshold (inclusive)" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold (inclusive)" ],
);

@usage_order = qw/host port user password warning critical/;

get_options();

($host, $port, $user, $password) = validate_host_port_user_password($host, $port, $user, $password);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1 } );

my $url = "http://$host:$port/rest/jobs/list-running";

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$status = "OK";

my $json = datameer_curl $url, $user, $password;

my $running_jobs = 0;
my %job_statuses = (
    "running"               => 0,
    "waiting_for_other_job" => 0,
);
foreach(@{$json}){
    $running_jobs++;
    defined($_->{"jobStatus"}) or quit "UNKNOWN", "no jobstatus returned from Datameer server. Format may have changed. $nagios_plugins_support_msg";
    $job_statuses{lc $_->{"jobStatus"}}++;
}

$msg = "active jobs=$running_jobs";

check_thresholds($running_jobs);

foreach(sort keys %job_statuses){
    $msg .= ", $_=$job_statuses{$_}";
}

$msg .= " | active_jobs=$running_jobs";
msg_perf_thresholds();

# Not adding variable perdata args as that can break PNP4Nagios
#foreach(sort keys %job_statuses){
foreach(qw/running waiting_for_other_job/){
    $msg .= " $_=$job_statuses{$_}";
}

quit $status, $msg;
