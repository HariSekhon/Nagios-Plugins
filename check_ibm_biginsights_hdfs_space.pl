#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights HDFS Space Used % via BigInsights Console REST API

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults(70, 90);

%options = (
    %hostoptions,
    %useroptions,
    %tlsoptions,
    %thresholdoptions,
);
@usage_order = qw/host port user password tls ssl-CA-path tls-noverify warning critical/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_thresholds();

tls_options();

vlog2;
set_timeout();

$status = "OK";

curl_biginsights "/ClusterStatus/fs_summary.json", $user, $password;

my $label = get_field("label");
$label eq "HDFS" or quit "UNKNOWN", "label returned was '$label' instead of 'HDFS'";
my $used            = get_field("used");
my $presentCapacity = get_field("presentCapacity");
my $remaining       = get_field("remaining");
if($presentCapacity == 0){
    quit "CRITICAL", "$presentCapacity capacity";
}
my $hdfs_pc = $used / $presentCapacity;
$msg .= sprintf("HDFS space used %.2f%%", $hdfs_pc);
check_thresholds($hdfs_pc);
$msg .= sprintf(" (%s/%s)", human_units($used), human_units($presentCapacity));
$msg .= sprintf(" | 'space used %%'=%.2f%%", $hdfs_pc);
msg_perf_thresholds();
$msg .= sprintf(" 'Used Capacity'=%db 'Present Capacity'=%db 'Remaining Capacity'=%db", $used, $presentCapacity, $remaining);

quit $status, $msg;
