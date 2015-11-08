#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2010-08-09 12:16:06 +0100 (Mon, 09 Aug 2010)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# Counts the number of errors in the log file specified and alerts if the number is greater than the given thresholds
# Designed to be called over NRPE or similar mechanism

$VERSION = "0.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $default_name  = "Log";
my $default_label = "errors";
my $exclude;
my $include;
my $logfile;
my $name = $default_name;
my $label = $default_label;

%options = (
    "l|logfile=s"  => [ \$logfile,  "The path to one or more logfiles, comma separated" ],
    "i|include=s"  => [ \$include,  "Regex to check the log for (ERE Regex)" ],
    "e|exclude=s"  => [ \$exclude,  "Exclusion regex (ERE Regex)" ],
    "n|name=s"     => [ \$name,     "Name of the log (ie Apache, Nginx, defaults to just '$default_name')" ],
    "label=s"      => [ \$label,    "Find LABEL lines instead of error lines" ],
    "w|warning=i"  => [ \$warning,  "The warning count threshold" ],
    "c|critical=i" => [ \$critical, "The critical count threshold" ],
);
@usage_order = qw/logfile include exclude name label warning critical/;

get_options();

defined($logfile)       || usage "logfile not defined";
sub validate_logfile{
    my $logf = shift;
    $logf =~ /^([\w\/\.-]+)$/ || usage "logfile '$$logf' name contains invalid characters";
    return $1;
}
if ($logfile =~ /,/) {
    my $tmplogfile;
    my $newlogstring = "";
    foreach $tmplogfile (split(",", $logfile)){
        #print "$tmplogfile\n";
        $tmplogfile =~ s/^\s*//;
        $tmplogfile =~ s/\s*$//;
        (-e $tmplogfile) || quit "UNKNOWN", "logfile '$tmplogfile' not found, non-existent or permission denied?";
        (-r $tmplogfile) || quit "UNKNOWN", "logfile '$tmplogfile' found but not readable";
        #print "calling validate_logfile($tmplogfile)\n";
        $tmplogfile = validate_logfile($tmplogfile);
        $newlogstring .= " \"$tmplogfile\"";
    }
    $logfile = $newlogstring;
} else {
    (-e $logfile)           || quit "UNKNOWN", "logfile '$logfile' not found, non-existant or permission denied?";
    (-r $logfile)           || quit "UNKNOWN", "logfile '$logfile' found but not readable";
    $logfile = validate_logfile($logfile);
    $logfile = "\"$logfile\"";
}
defined($warning)       || usage "warning threshold not defined";
defined($critical)      || usage "critical threshold not defined";
$warning  =~ /^\d+$/    || usage "invalid warning threshold given, must be a positive numeric integer";
$critical =~ /^\d+$/    || usage "invalid critical threshold given, must be a positive numeric integer";
($critical >= $warning) || usage "critical threshold must be greater than or equal to the warning threshold";

usage "Include regex not supplied" unless $include;

my $regex_filter = '^([\w%{}\/\\\[\]\(\)|:\s\.,\*\^-]+)$';
$include =~ /$regex_filter/i || quit "UNKNOWN", "unexpected include regex, aborting for security...";
$include = $1;
if($exclude){
    $exclude =~ /$regex_filter/i || quit "UNKNOWN", "unexpected exclude regex, aborting for security...";
    $exclude = $1;
}

$name =~ /^([\w\s\.-]+)$/ or quit "UNKNOWN", "invalid name given, stick to alphanumeric/whitespace";
$name = $1;

$label =~ /^([\w-]+)$/ or quit "UNKNOWN", "invalid name given, must be single alphanumeric word";
$label = $1;

set_timeout();

# logfile is quoted above, don't quote it again
my $cmd = "egrep -hi \"$include\" $logfile 2>&1";
$cmd .= " | egrep -vi \"$exclude\"" if $exclude;
my @output = cmd($cmd);
my $count = scalar(@output);
vlog2 "count: $count\n";

$label = lc $label;
my $label2 = ucfirst $label;
my $msg = "$count $label detected in log file '$logfile' (threshold w=$warning/c=$critical) | '$name $label2'=$count;$warning;$critical;0";

if($count > $critical){
    quit "CRITICAL", "$msg";
}elsif($count > $warning){
    quit "WARNING", "$msg";
}else{
    quit "OK", "$msg";
}
