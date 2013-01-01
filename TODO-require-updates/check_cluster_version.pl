#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-06-07 14:18:57 +0100 (Tue, 07 Jun 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

# TODO: need rewrite to use HariSekhonUtils.pm

# Nagios Plugin to check all instances of a cluster are the same version. Uses Nagios macros containing output of host specific checks showing the version strings in their output. Requires each server having a check outputting it's application version which this plugin then aggregates using the Nagios macros in the cluster service definition

$main::VERSION = "0.4";

use strict;
use warnings;
use Getopt::Long ":config";
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__);
}
use utils qw(%ERRORS $TIMEOUT);

delete @ENV{qw(IFS CDPATH ENV BASH_ENV)};
$ENV{'PATH'} = '/bin:/usr/bin';

my $progname = basename $0;

my $default_timeout = 10;

my $critical;
my $help;
my $ignore_nrpe_timeout = 0;
my $timeout = $default_timeout;
my $verbose = 0;
my $version;
my $warning;
my @data;

sub vlog{
    print "@_\n" if $verbose;
}

sub quit{
    print "$_[0]: $_[1]\n";
    exit $ERRORS{$_[0]};
}

sub usage {
    print "@_\n\n" if @_;
    quit "UNKNOWN", "usage: $progname [ options ]

    -d --data               Comma separated list of service outputs to compare (use Nagios macros to populate this)
    -w --warning            Warning threshold
    -c --critical           Critical threshold
    --ignore-nrpe-timeout   Ignore results matching 'CHECK_NRPE: Socket timeout after N seconds.'
    -t --timeout            Timeout in secs (default $default_timeout)
    -v --verbose            Verbose mode
    -V --version            Print version and exit
    -h --help --usage       Print this help
\n";
}

GetOptions (
            "h|help|usage"          => \$help,
            'd|data=s{,}'           => \@data,
            "w|warning=i"           => \$warning,
            "c|critical=i"          => \$critical,
            "ignore-nrpe-timeout"   => \$ignore_nrpe_timeout,
            "t|timeout=i"           => \$timeout,
            "v|verbose+"            => \$verbose,
            "version"               => \$version,
           ) or usage;

defined($help) and usage;
defined($version) and die "$progname version $main::VERSION\n";

vlog "verbose mode on";

defined($warning)       || usage "warning threshold not defined";
defined($critical)      || usage "critical threshold not defined";
$warning  =~ /^\d+$/    || usage "invalid warning threshold given, must be a positive numeric integer";
$critical =~ /^\d+$/    || usage "invalid critical threshold given, must be a positive numeric integer";
($warning  >= 2 )       || usage "warning threshold must be >= 2";
($critical >= 2 )       || usage "critical threshold must be >= 2";
($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

$timeout =~ /^\d+$/                 || die "timeout value must be a positive integer\n";
($timeout >= 1 && $timeout <= 60)   || die "timeout value must be between 1 - 60 secs\n";

$SIG{ALRM} = sub {
    quit "UNKNOWN", "check timed out after $timeout seconds\n";
};
print "setting plugin timeout to $timeout secs\n" if $verbose;
alarm($timeout);

@data || usage "no data set provided";
# TODO: review handling of this arg
@data = split(",", $data[0]);
foreach(@data){
    vlog "data set: $_";
}
my $data_num = scalar @data;
($data_num < 1 ) && usage "No data sets provided";
vlog "total data sets: $data_num";
vlog "warning threshold: $warning";
vlog "critical threshold: $critical";

($warning  > $data_num) && usage "warning threshold ($warning) cannot be greater than total data set provided ($data_num)!";
($critical > $data_num) && usage "critical threshold ($critical) cannot be greater than total data set provided ($data_num)!";

my %data2;
foreach(@data){
    # This will normalize Nagios status out of the equation
    # output string will be an important factor but you have to have faith that it remains constant, which it does since I wrote it
    # Also, it displays the outputs which is totally useful so you can see if that's what's up :)
    s/^(?:\w+\s+){0,3}(?:OK|WARN\w*|CRIT\w*|UNKNOWN):\s*//i;
    $data2{$_}++;
}
my $msg2 = "";
foreach(sort keys %data2){
    $msg2 .= "$data2{$_}x'$_', ";
    vlog "$data2{$_} x data set: $_";
}
$msg2 =~ s/, $//;
if($ignore_nrpe_timeout){
    foreach(keys %data2){
        if(/^CHECK_NRPE: Socket timeout after \d+ seconds?\.?$/){
            vlog "ignoring nrpe timeout results";
            delete $data2{$_};
        }
    }
}
my $num_different_versions = keys %data2;
vlog "total different versions: $num_different_versions";

my $msg = "$num_different_versions versions detected across cluster of $data_num (w=$warning/c=$critical) - $msg2";
if($num_different_versions >= $critical){
    quit "CRITICAL", "$msg";
} elsif($num_different_versions >= $warning){
    quit "WARNING", "$msg";
} else {
    quit "OK", "$msg";
}
