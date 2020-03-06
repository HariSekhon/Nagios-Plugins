#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-04-19 17:51:00 +0100 (Tue, 19 Apr 2011)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# TODO: reintegrate this with HariSekhonUtils

$main::VERSION = "0.1.1";

use strict;
use warnings;
use Getopt::Long qw(:config bundling);
use Sys::Hostname;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
# Redhat RPM utils.pm install location from nagios-plugins skeleton rpm
use lib '/usr/lib64/nagios/plugins';
# Debian monitoring-plugins-common and Alpine nagios-plugins utils.pm install location
use lib '/usr/lib/nagios/plugins';
#use lib '/usr/lib/icinga';
# Mac Homebrew utils.pm install location
use lib '/usr/local/nagios/libexec/sbin';
# custom
use lib '/usr/local/nagios/libexec';
use utils qw(%ERRORS $TIMEOUT);

# Make %ENV safer (taken from PerlSec)
delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

my $progname = basename $0;

# This improves stability as sometimes it takes a while for Nagios to process the NSCA result via the cmd pipe
my $sleep_secs = 60;
my $default_nagios_log  = "/var/log/nagios/nagios.log";
my $default_nsca_config = "/etc/nagios/send_nsca.cfg";
my $default_send_nsca   = "/usr/sbin/send_nsca";
my $default_timeout     = $sleep_secs + 10;
my $help;
my $host;
my $nagios_log  = $default_nagios_log;
my $nsca_config = $default_nsca_config;
my $send_nsca   = $default_send_nsca;
my $timeout     = $default_timeout;
my $verbose=0;
my $version;
our $cmd;
our $output;
our $result;

sub usage{
    print "@_\n" if @_;
    print "usage: $progname [ options ]

--host        -H    Remote NSCA Server to check (defaults to localhost. If supplied, does not check the log file)
--send_nsca   -s    Path to send_nsca binary    (defaults to $default_send_nsca)
--nsca_config -c    Path to send_nsca.cfg       (defaults to $default_nsca_config)
--nagios-log  -n    Path to the Nagios log file (defaults to $default_nagios_log)
--timeout     -t    Timeout in seconds          (defaults to $default_timeout, min 1, max 60)
--version     -V    Show version and exit
--verbose     -v    Verbose mode
--help        -h    Print this help
\n";
    exit $ERRORS{"UNKNOWN"};
}

GetOptions (
            "h|help"          => \$help,
            "H|host=s"        => \$host,
            "c|nsca_config=s" => \$nsca_config,
            "n|nagios-log=s"  => \$nagios_log,
            "s|send_nsca=s"   => \$send_nsca,
            "t|timeout=i"     => \$timeout,
            "v|verbose"       => \$verbose,
            "V|version"       => \$version,
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

if($host){
    $host =~ /^([\w\.-]+)$/ or quit "UNKNOWN", "invalid host given to check";
    $host = $1;
}

sub check_path {
    my $name = shift;
    my $path = shift;
    $path =~ /^([\w\.\/-]+)$/ or quit "UNKNOWN", "invalid path given for $name";
    return $1;
}

sub check_file {
    my $name = shift;
    my $file = shift;
    $file = check_path($name, $file);
    ( -e $file ) or quit "UNKNOWN", "file '$file' not found";
    ( -f $file ) or quit "UNKNOWN", "'$file' not a file";
    ( -r $file ) or quit "UNKNOWN", "file '$file' not readable";
    return $file;
}

$nsca_config = check_file("nsca config", $nsca_config);
$nagios_log  = check_file("nagios log",  $nagios_log) unless($host);
$send_nsca   = check_file("send_nsca",   $send_nsca);
$send_nsca =~ /send_nsca$/ or quit "UNKNOWN", "send_nsca binary does not end in send_nsca!";
( -x $send_nsca ) or quit "UNKNOWN", "'$send_nsca' is not executable";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 300)   || die "timeout value must 1 - 300 secs\n";

print "verbose mode on\n" if $verbose;

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
print "setting plugin timeout to $timeout secs\n" if $verbose;
alarm($timeout);

my $now = time;
my $hostname;
if($host){
    $hostname = $host;
    #if($hostname eq hostname){ undef $host; }
} else {
    $hostname = hostname;
    $hostname =~ /^([\w\.-]+)$/ or quit "UNKNOWN", "unrecognized hostname returned by Sys::Hostname";
    $hostname = $1;
}
my $success_msg = "NSCA throughput check successful $now";
my $log = "$hostname\\tNSCA\\t0\\t$success_msg";
my $nsca_log = '\[[[:digit:]]\+\] EXTERNAL COMMAND: PROCESS_SERVICE_CHECK_RESULT;' . $log;
$nsca_log =~ s/\\t/;/g;

sub print_cmd {
    if($verbose){
        chomp $output;
        print "\ncmd:         $cmd\n\n";
        print "output:      <$output>\n";
        print "return code: $result\n\n";
    }
}

$cmd = "printf '$log\\n' | '$send_nsca' -H $hostname -c '$nsca_config'";
$output = `$cmd`;
$result = $?;
print_cmd;

if(not $output =~ /^1 data packet\(s\) sent to host successfully\.$/){
    $output =~ s/\n/ /g;
    quit "CRITICAL", "Failed to send NSCA result:  $output";
}
chomp $output;
quit "OK", $output if($host);
print "sleeping for $sleep_secs secs to allow NSCA to feed result to Nagios\n" if $verbose;
sleep $sleep_secs;
$cmd = "grep '^$nsca_log\$' '$nagios_log'";
$output = `$cmd 2>&1`;
$result = $?;
my @output = split("\n", "$output");
my $lines = scalar(@output);
print_cmd;
$output = join(" ", @output);
my $debug_msg = "(lines: $lines, output: '$output')";
if($result == 0){
    if ($lines eq 1){
        quit "OK", "$success_msg ++";
    } elsif ($lines gt 1){
        quit "WARNING", "duplicate NSCA log detected $debug_msg'";
    } elsif ($lines eq 0){
        quit "CRITICAL", "code error, no NSCA log lines found! $debug_msg";
    } elsif ($lines lt 0){
        quit "CRITICAL", "code error, negative number of NSCA log lines found! $debug_msg";
    } else {
        quit "CRITICAL", "code error, unknown condition regarding number of log matches found $debug_msg";
    }
} else {
    quit "CRITICAL", "NSCA failed to feed result to Nagios $debug_msg";
}
quit "CRITICAL", "hit end of code";
