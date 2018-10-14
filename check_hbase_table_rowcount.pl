#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-13 02:30:13 +0100 (Sun, 13 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check the number of rows in an HBase table using hbase shell

Doing the count in hbase shell with tuned cached was tested to be much faster than trying to get the result over something like the Stargate API

On any non-test table with real data, this will take minutes or more, and you will need to adjust the --timeout accordingly.

Suggest this be run as a passive service check and the result fed back in to NSCA.

Tested on HBase 0.94 on CDH 4.3.0, 4.5.0 and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1
";

$VERSION = "0.3.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

set_timeout_max(86400);

my $table;
my $hbase_bin = "hbase";
if(-x "/opt/cloudera/parcels/CDH/bin/hbase"){
    $hbase_bin = "/opt/cloudera/parcels/CDH/bin/hbase";
} elsif(-x "/usr/lib/hbase/bin/hbase"){
    $hbase_bin = "/usr/lib/hbase/bin/hbase";
}
my $rowcount;

%options = (
    "T|table=s"     => [ \$table,       "HBase Table to collect row count for" ],
    "hbase-bin=s"   => [ \$hbase_bin,   "Path to hbase program, uses hbase shell for count as it was the fastest method when tested" ],
    %thresholdoptions,
);
@usage_order = qw/table hbase-bin warning critical/;

get_options();

$table     = validate_database_tablename($table, "HBase", "allow_qualified");
$hbase_bin = validate_file($hbase_bin, "hbase");
which($hbase_bin, 1);
$hbase_bin =~ /(.*\/?)hbase$/ or usage "invalid hbase-bin supplied, must be the path to the hbase command";
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

vlog2 "running hbase count against table '$table'\n";

my $cmd = "echo 'count \"$table\", CACHE => 1000' | $hbase_bin shell 2>&1";
vlog3 "cmd: $cmd";
my $start_time = time;
open my $fh, "$cmd |";
my $returncode = $?;
$returncode == 0 or quit "CRITICAL", <$fh>;
vlog3 "returncode: $returncode";
while(<$fh>){
    chomp;
    vlog3 "output: $_";
    /error/i and quit "CRITICAL", $_;
    if(/^(\d+)\s+row/){
        $rowcount = $1;
    }
}
my $time = time - $start_time;
vlog3;
defined($rowcount) or quit "UNKNOWN", "failed to find row count in output from hbase shell. $nagios_plugins_support_msg";

$msg = "$rowcount rows returned for table '$table'";
check_thresholds($rowcount);
$msg .= " | rows=$rowcount";
msg_perf_thresholds();
$msg .= " query_time=${time}s";

quit $status, $msg;
