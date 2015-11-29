#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-12-03 11:02:52 +0000 (Mon, 03 Dec 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the Linux system file descriptors % used on the local system. Call remotely via NRPE.

See also check_ulimit.pl in the Advanced Nagios Plugins Collection";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

set_threshold_defaults(70, 90);

%options = (
    %thresholdoptions,
);

get_options();

validate_thresholds();

linux_only();

vlog2;
set_timeout();

# same as the 3rd number from file-nr
#my $fh = open_file "/proc/sys/fs/file-max";
#my $limit = <$fh>;
#isInt $limit or quit "UNKNOWN", "failed to get system file max";
#vlog2 "system file max: $limit";

# http://www.netadmintools.com/part295.html
# https://access.redhat.com/documentation/en-US/Red_Hat_Enterprise_Linux/5/html/Tuning_and_Optimizing_Red_Hat_Enterprise_Linux_for_Oracle_9i_and_10g_Databases/chap-Oracle_9i_and_10g_Tuning_Guide-Setting_File_Handles.html
my $fh = open_file "/proc/sys/fs/file-nr";
vlog3 sprintf("\ncontents:\n\n%s\n", <$fh>);
seek($fh, 0, 0);
my ($allocated, $allocated_free, $limit) = split(/\s+/, <$fh>, 3);
isInt $allocated       or quit "UNKNOWN", "failed to get system files allocated";
isInt $allocated_free  or quit "UNKNOWN", "failed to get system files unallocated";
isInt $limit           or quit "UNKNOWN", "failed to get system files limit";
($allocated < $allocated_free) and quit "UNKNOWN", "code or /proc error, system file allocated < allocated_free!";

# second field was used file handles in 2.4 kernels so need to check kernel version
# see also http://man7.org/linux/man-pages/man5/proc.5.html:
# /proc/sys/kernel/ostype     => Linux
# /proc/sys/kernel/osrelease  => 2.6.32-358.2.1.el6.x86_64
# /proc/sys/kernel/version    => #1 SMP Wed Mar 13 00:26:49 UTC 2013
$fh = open_file "/proc/version";
<$fh> =~ /^Linux\s+version\s+(\d+\.\d+)\./ or quit "UNKNOWN", "failed to determine Linux kernel version to accurately calculate used file handles";
my $kernel_version = $1;
vlog2 "kernel version $kernel_version";
my $used;
if($kernel_version <= 2.4){
    $used = $allocated_free;
} else {
    $used = $allocated - $allocated_free;
}
vlog2 "system file descriptors used:  $used";
vlog2 "system file descriptors limit: $limit";

$status = "OK";

my $percentage = sprintf("%.2f", $used / $limit * 100);
$msg  = sprintf("%.2f%% system file descriptors used [%d/%d]", $percentage, $used, $limit);
check_thresholds($percentage);
$msg .= sprintf(" | 'system file descriptors %% used'=%.2f%%%s 'system file descriptors used'=%d", $percentage, msg_perf_thresholds(1), $used);

quit $status, $msg;
