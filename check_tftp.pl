#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-08-11 17:12:01 +0000 (Wed, 11 Aug 2010)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a TFTP Server is working by fetching a given file from the server

I originally wrote this to check my PXE boot servers were available and serving pxelinux";

$VERSION = "0.2";

use warnings;
use strict;
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

linux_only();

set_timeout($timeout, sub { `pkill -9 -f "$tftp $host $port"` });

which($tftp, 1);

my $output;
my $bytes_received;
my $bits_per_second;
my $transfer_seconds;

my $cmd = "$tftp -v $host $port -c get $filename";
vlog3 "cmd: $cmd\n";
open(CMD, "cd /tmp; exec $cmd 2>&1 |");
#local (*CMDR, *CMDW);
#open2(\*CMDR, \*CMDW, "$tftp $host $port 2>&1") or quit "CRITICAL", "can't open $tftp to $host on port $port: $!";
#print CMD "timeout " . ($timeout - 1) . "\n";
#print "set tftp timeout\n" if $verbose;
#print CMD "verbose\n";
#print CMD "get $filename\n";
vlog2 "sent request for file '$filename'\n";
while(<CMD>){
    chomp;
    vlog3 "tftp: $_";
    if(/Transfer timed out./){
        quit "CRITICAL", $_;
    }elsif(/Permission denied/){
        quit "CRITICAL", $_;
    }elsif(/unknown host/){
        quit "CRITICAL", $_;
    }
    #next if /^getting from/;
    if(/^Received (\d+) bytes in ([\d\.]+) seconds \[(\d+) bit\/s\]$/){
        #/^Received (\d+) bytes in ([\d\.]+) seconds \[(\d+) bit\/s\]$/
        $output           = $_;
        $bytes_received   = $1;
        $transfer_seconds = $2;
        $bits_per_second  = $3;
    }
}
close (CMD);
#close (CMDW);
#vlog2 "closed tftp pipe";
vlog3;
if(defined($output)){
} elsif(-f "/tmp/$filename" and -z "/tmp/$filename"){
    quit "OK", "fetched empty file from tftp server '$host:$port', not a great test, recommend to use a file with content instead";
} else {
    quit "CRITICAL", "transfer failed / unknown response from tftp";
}

$status = "OK";
$msg = "$output | 'Bits / second'=".$bits_per_second." 'Transfer Time'=".$transfer_seconds."s 'Bytes Received'=".$bytes_received."B";

quit $status, $msg;
