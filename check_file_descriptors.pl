#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-10-28 13:48:49 +0100 (Thu, 28 Aug 2010)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to count the number of total allocated file descriptors on a system. Designed to be called over NRPE";

$VERSION = 0.3;

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $procfile = "/proc/sys/fs/file-nr";

my $process;

%options = (
    "w|warning=s"   => [ \$warning,  "Warning  threshold or ran:ge (inclusive)" ],
    "c|critical=s"  => [ \$critical, "Critical threshold or ran:ge (inclusive)" ],
);

get_options();
validate_thresholds(1,1);
vlog2;

linux_only();

set_timeout();

my $fh = open_file $procfile;;
my ($file_descriptors_allocated, $file_descriptors_free, $max_file_descriptors) = split(/\s+/,<$fh>);
close $fh;
vlog2 "\nfile descriptors allocated = $file_descriptors_allocated";
vlog2 "file descriptors free      = $file_descriptors_free";
vlog2 "file descriptors max       = $max_file_descriptors\n";
isInt($file_descriptors_allocated) or quit "UNKNOWN", "failed to retrieve number of file descriptors, non-numeric value found for file_descriptors_allocated";
isInt($file_descriptors_free) or quit "UNKNOWN", "failed to retrieve number of file descriptors, non-numeric value found for file_descriptors_free";
isInt($max_file_descriptors) or quit "UNKNOWN", "failed to retrieve number of file descriptors, non-numeric value found for max_file_descriptors";

$status = "OK";

$msg = "$file_descriptors_allocated file descriptors allocated, $file_descriptors_free free, $max_file_descriptors max";
check_thresholds($file_descriptors_allocated);
$msg .= " | 'File Descriptors Allocated'=$file_descriptors_allocated;$warning;$critical 'File Descriptors Free'=$file_descriptors_free 'File Descriptors Maximum'=$max_file_descriptors";

quit $status, $msg;
