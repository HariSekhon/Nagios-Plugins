#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-08-11 17:12:01 +0000 (Wed, 11 Aug 2010)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Nagios Plugin to check a TFTP Server

$VERSION = "0.2";

use warnings;
use strict;
use Getopt::Long qw(:config bundling);
use IPC::Open2;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $tftp = "/usr/bin/tftp";
my $filename;
my $default_port = 69;
$port = $default_port;

%options = (
    "H|host=s"     => [ \$host,     "TFTP server" ],
    "p|port=i"     => [ \$port,     "TFTP port (defaults to port $default_port)" ],
    "f|file=s"     => [ \$filename, "File to retrieve over TFTP to check" ],
);
@usage_order = qw/host port file/;

get_options();

$host     = validate_host($host);
$port     = validate_port($port);
$filename = validate_filename($filename);

set_timeout($timeout, sub { `pkill -9 -f "$tftp $host $port"` });

which($tftp, 1);

my $output;
my $bytes_received;
my $bits_per_second;
my $transfer_seconds;

open(CMD, "cd /tmp; exec $tftp -v $host $port -c get $filename 2>&1 |");
#local (*CMDR, *CMDW);
#open2(\*CMDR, \*CMDW, "$tftp $host $port 2>&1") or quit "CRITICAL", "can't open $tftp to $host on port $port: $!";
#print CMD "timeout " . ($timeout - 1) . "\n";
#print "set tftp timeout\n" if $verbose;
#print CMD "verbose\n";
#print CMD "get $filename\n";
vlog2 "sent request for file '$filename'\n";
while(<CMD>){
    print "output: $_" if $verbose;
    if(/Transfer timed out./){
        quit "CRITICAL", "$_";
    }elsif(/Permission denied/){
        quit "CRITICAL", "$_";
    }elsif(/unknown host/){
        quit "CRITICAL", "$_";
    }
    next if /^getting from/;
    if(/^Received (\d+) bytes in ([\d\.]+) seconds \[(\d+) bit\/s\]$/){
        #/^Received (\d+) bytes in ([\d\.]+) seconds \[(\d+) bit\/s\]$/
        $output           = $_;
        $bytes_received   = $1;
        $transfer_seconds = $2;
        $bits_per_second  = $3;
        chomp $output;
    }
}
close (CMD);
#close (CMDW);
vlog2 "closed file handles";
defined($output) || quit "CRITICAL", "transfer failed / unknown response from tftp";

$status = "OK";
$msg = "$output | 'Bits / second'=".$bits_per_second." 'Transfer Time'=".$transfer_seconds."s 'Bytes Received'=".$bytes_received."B";

quit $status, $msg;
