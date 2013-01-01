#!/usr/bin/perl -T
# nagios: -epn
#
#   Author: Hari Sekhon
#   Date: 2011-07-26 15:27:47 +0100 (Tue, 26 Jul 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# TODO: updates and extensions pending on this plugin. Also must be reintegrated with HariSekhonUtils

# Nagios Plugin to monitor Zookeeper

$main::VERSION = "0.2";

use strict;
use warnings;
use Fcntl ':flock';
use IO::Socket;
use Getopt::Long qw(:config bundling);
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use utils qw(%ERRORS $TIMEOUT);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

my $progname = basename $0;
$progname =~ /^([\w\.\/-]+)$/;
$progname = $1;

my $default_timeout = 10;
my $help;
my $timeout = $default_timeout;
my $verbose = 0;
my $version;

sub vlog{
    print "@_\n" if $verbose;
}

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

my $critical;
my $default_port = 2181;
my $host;
my $port = $default_port;
my $warning;
sub usage {
    print "@_\n\n" if defined(@_);
    print "usage: $progname [ options ]

    -H --host           Host to connect to
    -p --port           Port to connect to (defaults to $default_port)
    -t --timeout        Timeout in secs (default $default_timeout)
    -v --verbose        Verbose mode
    -V --version        Print version and exit
    -h --help --usage   Print this help
\n";
    exit $ERRORS{"UNKNOWN"};
}

GetOptions (
            "h|help|usage"  => \$help,
            "H|host=s"      => \$host,
            "p|port=s"      => \$port,
#            "w|warning=i"   => \$warning,
#            "c|critical=i"  => \$critical,
            "t|timeout=i"   => \$timeout,
            "v|verbose+"    => \$verbose,
            "V|version"     => \$version,
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

vlog "verbose mode on";

defined($host)                  || usage "hostname not specified";
$host =~ /^([\w\.-]+)$/         || die "invalid hostname given\n";
$host = $1;

defined($port)                 || usage "port not specified";
$port  =~ /^(\d+)$/             || die "invalid port number given, must be a positive integer\n";
$port = $1;
($port >= 1 && $port <= 65535)  || die "invalid port number given, must be between 1-65535)\n";

#defined($warning)       || usage "warning threshold not defined";
#defined($critical)      || usage "critical threshold not defined";
#$warning  =~ /^\d+$/    || usage "invalid warning threshold given, must be a positive numeric integer";
#$critical =~ /^\d+$/    || usage "invalid critical threshold given, must be a positive numeric integer";
#($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must be between 1 - 60 secs\n";

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
vlog "setting plugin timeout to $timeout secs\n";
alarm($timeout);

vlog "Host: $host";
vlog "Port: $port\n";

vlog "connecting to $host:$port\n";
my $conn = IO::Socket::INET->new (
                                    Proto    => "tcp",
                                    PeerAddr => $host,
                                    PeerPort => $port,
                                 ) or quit "CRITICAL", "Failed to connect to '$host:$port': $!";
vlog "OK connected";
$conn->autoflush(1);
vlog "set autoflush on";

my %stats = (
    "Received"      => "",
    "Sent"          => "",
    "Outstanding"   => "",
    "Node count"    => "",
);

vlog "sending srvr request";
print $conn "srvr\n" or quit "CRITICAL", "Failed to send srvr request: $!";
vlog "srvr request sent";
my $line;
my $linecount = 0;
my $err_msg;
my $zookeeper_version;
my $latency_stats;
my $mode;
#vlog "Output:";
while (<$conn>){
    chomp;
    s/\r$//;
    #vlog "$_";
    if(/not currently serving requests/){
        quit "CRITICAL", "$_";
    }
    if(/ERROR/i){
        quit "CRITICAL", "unknown error returned from zookeeper on '$host:$port': '$_'";
    }
    #vlog "processing line: '$_'";
    $line = $_;
    $linecount++;
    if(/^Zookeeper version/i){
        $zookeeper_version = $line;
    } elsif(/^Latency/i){
        $latency_stats = $line;
    } elsif(/^Mode:/i){
        $mode = $line;
    } else {
        foreach(sort keys %stats){
            #vlog "checking for stat $_";
            if($line =~ /^$_: ([\d]+)$/){
                #vlog "found $_";
                $stats{$_} = $1;
                next;
            }
        }
    }
}
vlog "got response" if ($linecount > 0);
close $conn;
vlog "closed connection\n";

foreach(sort keys %stats){
    defined($stats{$_}) or quit "CRITICAL", "$_ was not found in output from zookeeper on '$host:$port'";
}

my $tmpfh;
my $statefile = "/tmp/$progname.$host.$port.state";
print "opening state file '$statefile'\n\n" if $verbose;
if(-f $statefile){
    open $tmpfh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    open $tmpfh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
}
flock($tmpfh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";
my $last_line = <$tmpfh>;
my $now = time;
my $last_timestamp;
my %last_stats;
if($last_line){
    print "last line of state file: <$last_line>\n\n" if $verbose;
    if($last_line =~ /^(\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s*$/x){
        $last_timestamp             = $1;
        $last_stats{"Node count"}   = $2,
        $last_stats{"Outstanding"}  = $3,
        $last_stats{"Received"}     = $4,
        $last_stats{"Sent"}         = $5,
    } else {
        print "state file contents didn't match expected format\n\n";
    }
} else {
    print "no state file contents found\n\n" if $verbose;
}
my $missing_stats = 0;
foreach(keys %last_stats){
    unless($last_stats{$_} =~ /^\d+$/){
        print "'$_' stat was not found in state file\n";
        $missing_stats = 1;
        last;
    }
}
if(not $last_timestamp or $missing_stats){
        print "missing or incorrect stats in state file, resetting to current values\n\n";
        $last_timestamp = $now;
}
seek($tmpfh, 0, 0)  or quit "UNKNOWN", "Error: seek failed: $!\n";
truncate($tmpfh, 0) or quit "UNKNOWN", "Error: failed to truncate '$statefile': $!";
print $tmpfh "$now ";
foreach(sort keys %stats){
    print $tmpfh "$stats{$_} ";
}
close $tmpfh;

my $secs = $now - $last_timestamp;

if($secs < 0){
    quit "UNKNOWN", "Last timestamp was in the future! Resetting...";
} elsif ($secs == 0){
    quit "UNKNOWN", "0 seconds since last run, aborting...";
}

my %stats_diff;
foreach(sort keys %stats){
    $stats_diff{$_} = int((($stats{$_} - $last_stats{$_} ) / $secs) + 0.5);
    if ($stats_diff{$_} < 0) {
        quit "UNKNOWN", "recorded stat $_ is higher than current stat, resetting stats";
    }
}

if($verbose){
    print "epoch now:                           $now\n";
    print "last run epoch:                      $last_timestamp\n";
    print "secs since last check:               $secs\n\n";
    printf "%-20s %-20s %-20s %-20s\n", "Stat", "Current", "Last", "Diff/sec";
    foreach(sort keys %stats_diff){
        printf "%-20s %-20s %-20s %-20s\n", $_, $stats{$_}, $last_stats{$_}, $stats_diff{$_};
    }
    print "\n\n";
}

my $msg = "$zookeeper_version, $latency_stats, $mode|";
foreach(sort keys %stats_diff){
    $msg .= "'$_'=$stats_diff{$_} ";
}
quit "OK", "$msg";
