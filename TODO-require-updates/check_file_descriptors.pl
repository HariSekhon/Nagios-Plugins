#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-10-28 13:48:49 +0100 (Thu, 28 Aug 2010)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# Counts the number of allocated file descriptors on a system
# Designed to be called over NRPE or similar mechanism

$main::VERSION = 0.3;

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use utils qw(%ERRORS $TIMEOUT);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

my $progname = basename $0;
my $procfile = "/proc/sys/fs/file-nr";

my $critical;
my $default_timeout = 10;
my $help;
my $process;
my $timeout = $default_timeout;
my $verbose=0;
my $version;
my $warning;

sub usage{
    print "@_\n" if defined(@_);
    print "usage: $progname [ -p <process_regex> ] -w <warning_count> -c <critical_count> [ -t <secs> ]

--process  -p    Process regex to fetch out of the process list
--warning  -w    The warning count threshold
--critical -c    The critical count threshold
--timeout  -t    Timeout in seconds (defaults to $default_timeout, min 1, max 60)
\n";
    exit $ERRORS{"UNKNOWN"};
}

GetOptions (
            "h"   => \$help,     "help"       => \$help,
            "p=s" => \$process,  "process=s"  => \$process,
            "w=i" => \$warning,  "warning=i"  => \$warning,
            "c=i" => \$critical, "critical=i" => \$critical,
            "t=i" => \$timeout,  "timeout=i"  => \$timeout,
            "v"   => \$verbose,  "verbose"    => \$verbose,
            "V"   => \$version,  "version"    => \$version
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

defined($warning)       || usage "warning threshold not defined";
defined($critical)      || usage "critical threshold not defined";
$warning  =~ /^\d+$/    || usage "invalid warning threshold given, must be a positive numeric integer";
$critical =~ /^\d+$/    || usage "invalid critical threshold given, must be a positive numeric integer";
($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must 1 - 60 secs\n";

if ( defined($process) ) {
    $process =~ /^([\w\s\[\]_-\.\*]+)$/ || die "Invalid process regex, disallowed characters present";
    $process = $1;
}

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
print "setting plugin timeout to $timeout secs\n" if $verbose;
alarm($timeout);

if ( defined($process) ) {
}
else {
    print "opening '$procfile'\n" if $verbose;
    open FILE, $procfile or die "failed to open '$procfile'\n";
    my ($file_descriptors_allocated, $file_descriptors_free, $max_file_descriptors) = split(/\s+/,<FILE>);
    close FILE;
    print "file descriptors allocated = $file_descriptors_allocated\nfile descriptors free = $file_descriptors_free\nmax file descriptors = $max_file_descriptors\n" if $verbose;

    if($file_descriptors_allocated !~ /^[\d\n]+$/  or
       $file_descriptors_free      !~ /^[\d\n]+$/  or
       $max_file_descriptors       !~ /^[\d\n]+$/){
        quit "UNKNOWN", "failed to retrieve number of file descriptors, non-numeric value was found";
    }

my $msg = "$file_descriptors_allocated file descriptors allocated, $file_descriptors_free free, $max_file_descriptors max (allocated threshold w=$warning/c=$critical) | 'File Descriptors Allocated'=$file_descriptors_allocated;$warning;$critical 'File Descriptors Free'=$file_descriptors_free 'Maximum File Descriptors'=$max_file_descriptors";

if($file_descriptors_allocated > $critical){
    quit "CRITICAL", "$msg";
}elsif($file_descriptors_allocated > $warning){
    quit "WARNING", "$msg";
}else{
    quit "OK", "$msg";
}
