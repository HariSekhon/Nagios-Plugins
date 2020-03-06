#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-03-30 17:34:04 +0000 (Wed, 30 Mar 2011)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Designed to be called from a log monitoring tool on receipt of a syslog-ng stats log and fed to Nagios via passive_wrapper and NSCA

$main::VERSION = "0.5.1";

use strict;
use warnings;
use Fcntl ':flock';
use Getopt::Long qw(:config bundling);
use POSIX;
use Time::Local;
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
$progname =~ /^([\w_\.-]+)$/ or die "script name was invalid\n";
$progname = $1;

my $default_critical = 1;
my $default_timeout  = 10;
my $default_warning  = 1;

my $critical = $default_critical;
my $help;
my $last_tstamp;
my $log;
my $msg  = "";
my $msg2 = "";
my $msg3 = "";
my $regex_types = "";
my $stat_dest;
my $stat_num;
my $stat_type;
my $statefh;
my $statefile;
my $status = "OK";
my $stdin;
my $timeout = $default_timeout;
my $type;
my $verbose;
my $version;
my $warning = $default_warning;
my %last_stats;
my %stats;
my %types = ( "dropped" => 0, "processed" => 0, "suppressed" => 0);
foreach my $regex_type (sort keys %types){
    $regex_types .= "$regex_type|";
}
$regex_types =~ s/\|$//;

my $regex_log_prefix = '^(\w+)\s+(\d+)\s+(\d{1,2}):(\d{1,2}):(\d{1,2})\s+([\w\.-]+)\s+syslog-ng\[\d+\]:\s+Log statistics;\s';
# Note: important that quotes are stripped later with s/[\\"']+//g
my $regex_dest = '[\w\s/\.\*\\\\"\':=-]+';
#my $regex_log_format = "$regex_log_prefix((?:$regex_types)='\\w+\\([\\w\\.:]+\\)=\\d+'(?:,\\s)?)+\$";
#^\w+\s+\d+\s+\d+:\d+:\d+\s+[\w\.-]+\s+syslog-ng\[\d+\]:\s+Log statistics;\s((?:dropped|processed|suppressed)='\w+\([\w\s/\.\*:=-]+\)=\d+'(?:,\s)?)+$
my $regex_log_format = "$regex_log_prefix((?:$regex_types)=" . '\'\w+\(' . "$regex_dest" . '\)=\d+\'(?:,\s)?)+$';

sub usage{
    print "@_\n\n" if @_;
    print "usage: $progname <-s|-l \"log string\"> [ -w <warning_count> -c <critical_count> -t <secs> ]

Warning/Critical thresholds only apply to dropped/suppressed unless targeting --processed

--log        -l  Log string, should be quoted of course
--stdin      -s  Get log from first line of stdin instead of as an arg, mutually exclusive with --log
--warning    -w  The warning count threshold for suppressed/dropped. Defaults to $default_warning
--critical   -c  The critical count threshold for suppressed/dropped. Defaults to $default_critical
--droppped   -d  Output only dropped stats
--processed  -p  Output only processed stats
--suppressed -s  Output only suppressed stats
--timeout    -t  Timeout in seconds (defaults to $default_timeout, min 1, max 60)
--version    -V  Show version and exit
--verbose    -v  Verbose mode
\n";
    exit $ERRORS{"UNKNOWN"};
}

GetOptions (
            "h|help"        => \$help,
            "l|log=s"       => \$log,
            "s|stdin"       => \$stdin,
            "D|dropped"     => \$types{"dropped"},
            "P|processed"   => \$types{"processed"},
            "S|suppressed"  => \$types{"suppressed"},
            "w|warning=i"   => \$warning,
            "c|critical=i"  => \$critical,
            "t|timeout=i"   => \$timeout,
            "v|verbose"     => \$verbose,
            "V|version"     => \$version,
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

defined($warning)       || usage "warning threshold not defined";
defined($critical)      || usage "critical threshold not defined";
$warning  =~ /^\d+$/ && ($warning  > 0) || usage "invalid warning threshold given, must be a positive numeric integer";
$critical =~ /^\d+$/ && ($critical > 0) || usage "invalid critical threshold given, must be a positive numeric integer";
($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must 1 - 60 secs\n";

my $type_count = 0;
foreach(sort keys %types){
    if($types{$_} > 0){
        $type_count++;
    }
}
($type_count > 1) && usage "dropped/processed/suppressed switches are mutually exclusive!";

print "verbose mode on\n\n" if $verbose;

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds";
};
print "setting plugin timeout to $timeout secs\n" if $verbose;
alarm($timeout);

$stdin && defined($log) && usage "cannot use both stdin and log switches";
if($stdin){
    print "getting log from first line of standard input\n" if $verbose;
    $log = <STDIN>;
}
print "\nlog validation regex: $regex_log_format\n\n" if $verbose;
defined($log)                  || usage "log string not given";
chomp $log;
$log =~ /($regex_log_format)/  || die "invalid log format given, offending log was: \"$log\"\n";
$log = $1;

print "\nlog: $log\n\n" if $verbose;

#$log="Mar 30 18:26:24 pixel303-dc3 syslog-ng[15962]: Log statistics; dropped='tcp(10.3.71.72:514)=0', dropped='tcp(10.3.71.71:514)=0', processed='center(queued)=2852', processed='center(received)=1426', processed='destination(d_boot)=0', processed='destination(d_auth)=10', processed='destination(d_net)=1426', processed='destination(d_cron)=26', processed='destination(d_mlal)=0', processed='destination(d_kern)=0', processed='destination(d_mesg)=1386', processed='destination(d_cons)=0', processed='destination(d_spol)=0', processed='destination(d_mail)=4', processed='source(s_sys)=1426', suppressed='tcp(10.3.71.72:514)=0', suppressed='tcp(10.3.71.71:514)=0'";

$log =~ /^$regex_log_format/ or quit "UNKNOWN", "Error: could not find hostname from log\n";
my $month = $1;
my $day   = $2;
my $hour  = $3;
my $min   = $4;
my $sec   = $5;
my $host  = $6;
my $year  = strftime("%Y", localtime);
my $current_month = strftime("%m", localtime);
my %mon2num = qw(
  jan 1  feb 2  mar 3  apr 4  may 5  jun 6
  jul 7  aug 8  sep 9  oct 10 nov 11 dec 12
);
my $mon = $mon2num{ lc substr($month, 0, 3) };

if($current_month < "$mon"){ $year-=1; }
if($verbose){
    print "\nhost:  $host\n\n";
    print "Year:  $year\n";
    print "Month: $month ($mon)\n";
    print "Day:   $day\n";
    print "Hour:  $hour\n";
    print "Min:   $min\n";
    print "Sec:   $sec\n";
}
my $tstamp = strftime("%s", $sec, $min, $hour, $day, $mon, $year - 1900);
    print "Epoch: $tstamp\n\n" if $verbose;
$log =~ s/$regex_log_prefix//;
foreach my $stat_section (split(",", $log)){
    $stat_section =~ s/^\s+//;
    $stat_section =~ s/\s+$//;
    #print "stat section: $stat_section\n";
    my $stat_num = $stat_dest = $stat_type = $stat_section;
    $stat_type =~ s/=.*$//;
    grep {$_ eq $stat_type} (sort keys %types) or die "'$stat_type' was not one of the expected stats types!\n";
    $stat_dest =~ s/^.*?='//;
    $stat_dest =~ s/=\d+'$//;
    $stat_dest =~ s/\s.*$/)/;
    $stat_num  =~ s/^.*=//;
    $stat_num  =~ s/['\s]+//;
    #print "x=$stat_type y=$stat_dest z=$stat_num\n" if $verbose;
    $stat_num  =~ /^\d+$/ || die "Error processing, failed to get number from '$stat_section' portion of log\n";
    $stats{$stat_type}{$stat_dest} = $stat_num;
}
print "\n" if $verbose;

sub check_type_thresholds {
    my $type = $_[0];
    my $dest2;
    my $dest;
    my $diff;
    my $diff_secs;
    my $increase;
    my $num;
    $statefile = "/tmp/$progname.$host.$type.tmp";
    if(-f $statefile){
        print "opening" if $verbose;
        open $statefh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
    } else {
        print "creating" if $verbose;
        open $statefh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
    }
    print " state file '$statefile'\n\n" if $verbose;
    flock($statefh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";

    my $regex_state_line = '^(\d+) (\w+\(' . $regex_dest . '\)) (\d+)$';
    print "checking state file against regex: '$regex_state_line'\n\n" if $verbose;
    my $state_lines = 0;
    while(<$statefh>){
        chomp;
        $state_lines += 1;
        /$regex_state_line/ or quit "UNKNOWN", "Error: state file '$statefile' was not in the expected format, offending line was \"$_\"";
        $last_tstamp           = $1;
        $last_stats{$type}{$2} = $3;
    }

    if($last_tstamp){
        $diff_secs = $tstamp - $last_tstamp;
    } else {
        $diff_secs = 0;
    }
    print "$diff_secs secs since last run\n\n" if $verbose;
    if($diff_secs > 0){
        seek($statefh, 0, 0)  or quit "UNKNOWN", "Error: seek failed: $!\n";
        truncate($statefh, 0) or quit "UNKNOWN", "Error: failed to truncate '$statefile': $!";
    } else {
        print "not updating state file since 0 secs since last run\n\n" if $verbose;
    }
    foreach(keys(%{$stats{$type}})){
        $dest = $dest2 = $_;
        $dest2 =~ s/^.*?\(//;
        $dest2 =~ s/\).*?$//;
        $dest2 =~ s/[\\'"]+//g;
        $num  = $stats{$type}{$dest};
        #print "dest: $dest\n";
        #print "num:  $num\n";
        print $statefh "$tstamp $dest $num\n" if ($diff_secs > 0 or $state_lines == 0);
        #foreach(keys %{$last_stats{$type}}){ print "last $_: $last_stats{$type}{$_}\n"; }
        if($last_stats{$type}{$dest}){
            if($num < $last_stats{$type}{$dest}){
                # This means syslog-ng has been restarted and the counters were reset
                $increase = $num;
            } else {
                $increase = $num - $last_stats{$type}{$dest};
            }
        } else {
            $increase = 0;
        }
        if($diff_secs > 0){
            $diff = int( ($increase / $diff_secs) + 0.5 );
        } else {
            $diff = 0
        }
        print "$increase increase in $dest in $diff_secs secs since last run\n$diff average logs per second\n\n" if $verbose;
        if($diff >= $critical){
            $status = "CRITICAL";
        } elsif($diff >= $warning) {
            $status = "WARNING";
        }
        if($type_count){
            $msg2 .= "$dest2=$diff";
            $msg3 .= "'$dest2'=$diff";
        } else {
            $msg2 .= "${dest}_$type=$diff";
            $msg3 .= "'${dest}_$type'=$diff";
        }
        if($type_count or $type eq "dropped" or $type eq "suppressed"){
            $msg3 .= ";$warning;$critical";
        }
        $msg2 .= " ";
        $msg3 .= " ";
    }
}

foreach $type (sort keys %types){
    if($type_count){
        if($types{$type}){
            check_type_thresholds($type);
            last;
        }
    } else {
        check_type_thresholds($type);
    }
    if($status eq "CRITICAL"){
        $msg .= "$type count >= $critical ";
    } elsif($status eq "WARNING"){
        $msg .= "$type count >= $warning ";
    }
}

$msg .= "$msg2";
$msg .= "(w=$warning/c=$critical) ";
$msg .= "| $msg3";
quit($status, $msg);
