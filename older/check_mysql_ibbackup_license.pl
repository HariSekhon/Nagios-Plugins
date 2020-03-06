#!/usr/bin/perl -T
#
#  Author: Hari Sekhon
#  Date: 2010-08-23 12:44:55 +0000 (Mon, 23 Aug 2010)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Checks local MySQL ibbackup license expiry

use warnings;
use strict;
use Getopt::Long qw(:config bundling);
use POSIX;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
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
use utils qw(%ERRORS);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

# This means no CPAN module deps or anything, it just works
my $date             = "/bin/date";
my $default_ibbackup = "/bin/ibbackup";
my $default_warning  = 30;
my $default_critical = 14;
my $default_timeout  = 10;
my $ibbackup         = $default_ibbackup;
my $warning          = $default_warning;
my $critical         = $default_critical;
my $timeout          = $default_timeout;
my $verbose;
my $help;
my $year;
my $month;
my $day;
my $time;

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

my $progname = basename $0;

sub usage{
    print "@_\n" if @_;
    print "usage: $progname [ -p /path/to/ibbackup -w <days> -c <days> -v ]

--path     -p    The path to the ibbackup binary (defaults to $default_ibbackup)
--warning  -w    The warning threshold in days   (defaults to $default_warning)
--critical -c    The critical threshold in days  (defaults to $default_critical)
--timeout  -t    Timeout in secs                 (defaults to $default_timeout)
--verbose  -v    Debug mode

Note: It usually takes 3/4 days to obtain a new license so it is not advised to set the thresholds to less than that
\n";
    exit $ERRORS{"UNKNOWN"};
}

GetOptions(
    "h"   => \$help,     "help"       => \$help,
    "p=s" => \$ibbackup, "path=s"     => \$ibbackup,
    "t=i" => \$timeout,  "timeout=i"  => \$timeout,
    "v"   => \$verbose,  "verbose"    => \$verbose,
    "w=i" => \$warning,  "warning=i"  => \$warning,
    "c=i" => \$critical, "critical=i" => \$critical,
) or usage;

defined($help) and usage;

$ibbackup =~ /^((?:\/[\w-]+)+\/ibbackup)$/ or usage "invalid path to ibbackup!";
$ibbackup = $1;
( -e $ibbackup) or quit "UNKNOWN", "'$ibbackup' was not found, either missing or permission denied";
( -x $ibbackup) or quit "UNKNOWN", "'$ibbackup' not executable! try 'chmod +x $ibbackup'";

$warning =~ /^(\d+)$/ or usage "warning threshold must be a positive integer";
$warning = $1;
($warning  >= 1 and $warning  <= 90) or usage "warning threshold must be between 1 and 90 days";

$critical =~ /^(\d+)$/ or usage "critical threshold must be a positive integer";
$critical = $1;
($critical >= 1 and $critical <= 90) or usage "critical threshold must be between 1 and 90 days";

$timeout =~ /^(\d+)$/ or usage "timeout must be a positive integer (secs)";
$timeout = $1;
($timeout >= 1 and $timeout <= 60) or usage "timeout must be between 1 and 60 seconds";

$SIG{ALRM} = sub {
    #`pkill -9 -f "^$ibbackup\$"`;
    quit "UNKNOWN", "check timed out after $timeout seconds";
};

print "setting timeout to $timeout seconds\n" if $verbose;
alarm($timeout);

print "cmd: $ibbackup\n" if $verbose;
my $ibbackup_output = `$ibbackup`;
print "output:\n\n$ibbackup_output\n" if $verbose;

# Expires 2010-8-1 (year-month-day) at 00:00
$ibbackup_output =~ /\nExpires (\d+)-(\d+)-(\d+) \(year-month-day\) at (\d\d:\d\d)\n/
    or quit "CRITICAL", "unable to determine expiry of ibbackup license due to unrecognized output from '$ibbackup'";
$year  = $1;
$month = $2;
$day   = $3;
$time  = $4;

# This means no CPAN module deps or anything, it just works
my $expiry_epoch = `$date -d "$month/$day/$year $time" '+%s'`;
my $epoch        = `$date '+%s'`;
chomp $expiry_epoch;
chomp $epoch;
if ($verbose) {
    print "expiry epoch: $expiry_epoch\n";
    print "now    epoch: $epoch\n\n";
}
$expiry_epoch =~ /^(\d+)$/ or quit "CRITICAL", "failed to determine expiry time";
$expiry_epoch = $1;
$epoch        =~ /^(\d+)$/ or quit "CRITICAL", "failed to determine current time";
$epoch        = $1;

my $days_left = ( ($expiry_epoch - $epoch) / 86000);
$days_left = floor($days_left);

my $msg = "$days_left days left on license";

if ($days_left < 0 ) {
    quit "CRITICAL", "license expired " . abs($days_left) . " days ago";
}
elsif ($days_left < $critical) {
    quit "CRITICAL", $msg;
}
elsif ($days_left < $warning) {
    quit "WARNING", $msg;
}
else {
    quit "OK", $msg;
}

quit "UNKNOWN", "hit end of code"
