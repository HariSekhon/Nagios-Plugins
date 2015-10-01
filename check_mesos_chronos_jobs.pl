#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-01 17:25:20 +0100 (Thu, 01 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check number of Chronos jobs

Optional thresholds apply to minimum number of jobs but can use standard nagios threshold format of <min>:<max> for each threshold to check max number of jobs

Tested on Chronos 2.5.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';

set_port_default(8080);
#set_threshold_defaults(1, 0);

env_creds("Chronos");

%options = (
    %hostoptions,
    %thresholdoptions,
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
validate_thresholds(0, 0, { 'simple' => 'lower', 'integer' => 1, 'positive' => 1 });

vlog2;
set_timeout();

$status = "OK";

my $url = "http://$host:$port/scheduler/jobs";
$json = curl_json $url, "Chronos scheduler jobs";
vlog3 Dumper($json);

my $num_jobs = scalar @{$json};

$msg = "Chronos number of jobs = $num_jobs";
check_thresholds($num_jobs);
$msg .= " | number_of_jobs=$num_jobs";
msg_perf_thresholds(0, 'lower');

vlog2;
quit $status, $msg;
