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

# TODO: reintegrate this with HariSekhonUtils

# Nagios Plugin to check a TFTP Server

$main::VERSION = 0.1;
my $tftp       = "/usr/bin/tftp";

use warnings;
use strict;
use Getopt::Long qw(:config bundling);
use IPC::Open2;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use utils qw(%ERRORS);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

my $help;
my $host;
my $port             = 69;
my $filename;
my $progname         = basename $0;
my $default_timeout  = 10;
my $timeout          = $default_timeout;
my $verbose;
my $version;

sub quit{
    print "TFTP $_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

sub usage{
    print "Error: @_\n\n" if defined(@_);
    print "usage: $progname -H <host> [ -p <port> ] -f <filename>

--host     -h    The host to check
--port     -p    The port to check (defaults to port 69)
--filename -f    File to retrieve
--timeout  -t    Timeout in seconds (defaults to $default_timeout, min 1, max 60)
\n";
    exit $ERRORS{"UNKNOWN"};
}

$SIG{ALRM} = sub {
    `pkill -9 -f "$tftp $host $port"`;
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
alarm($timeout);

GetOptions (
            "H=s" => \$host,     "host=s"     => \$host,
            "p=i" => \$port,     "port=i"     => \$port,
            "f=s" => \$filename, "file=s"     => \$filename,    "filename=s" => \$filename,
            "t=i" => \$timeout,  "timeout=i"  => \$timeout,
            "v"   => \$verbose,  "verbose"    => \$verbose,
            "V"   => \$verbose,  "version"    => \$version
           );

$version && die "$progname $main::VERSION\n";
$help    && usage;

$host                               || usage "hostname not specified";
$host =~ /^([\w\.-]+)$/             || die "invalid hostname given\n";
$host = $1;

#$port                               || usage "port not specified";
$port  =~ /^(\d+)$/                 || die "invalid port number given, must be a positive integer\n";
$port = $1;
($port >= 1 && $port <= 65535)      || die "invalid port number given, must be between 1-65535)\n";

$filename                           || usage "filename not specified";
$filename =~ /^([\w\.\/-]+)$/       || die "invalid file name given, must contain only alphanumeric characters and the following symbols . / - _";
$filename = $1;

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must 1 - 60 secs\n";

if(! -r $tftp){
    quit "UNKNOWN", "$tftp not found, missing or permission denied?";
}elsif(! -x $tftp){
    quit "UNKNOWN", "$tftp not executable";
}

if($verbose){
    print "verbose mode on\n\n";
    print "host:     $host\n";
    print "port:     $port\n";
    print "filename: $filename\n\n";
}

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
print "sent request for file '$filename'\n\n" if $verbose;
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
print "closed file handles\n" if $verbose;
defined($output) || quit "CRITICAL", "transfer failed / unknown response from tftp";

my $msg = "$output | 'Bits / second'=".$bits_per_second." 'Transfer Time'=".$transfer_seconds."s 'Bytes Received'=".$bytes_received."B";

quit "OK", "$msg";
