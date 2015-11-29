#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-06-07 14:18:57 +0100 (Tue, 07 Jun 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check all instances of a cluster are the same version. Uses Nagios macros containing output of host specific checks showing the version strings in their output. Requires each server having a check outputting it's application version which this plugin then aggregates using the Nagios macros in the cluster service definition";

$VERSION = "0.5";

use strict;
use warnings;
use Getopt::Long ":config";
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $data;
my $ignore_nrpe_timeout = 0;

%options = (
    'd|data=s'              => [ \$data,                "Comma separated list of service outputs to compare (use Nagios macros to populate this). Additional non-option arguments are added to this list for convenience" ],
    "w|warning=i"           => [ \$warning,             "Warning threshold or ran:ge (inclusive)"  ],
    "c|critical=i"          => [ \$critical,            "Critical threshold or ran:ge (inclusive)" ],
    "ignore-nrpe-timeout"   => [ \$ignore_nrpe_timeout, "Ignore results matching 'CHECK_NRPE: Socket timeout after N seconds.'" ],
);
@usage_order = qw/data warning critical ignore-nrpe-timeout/;

get_options();

validate_thresholds(1, 1, { "simple" => "upper", "integer" => 1, "positive" => 1} );
vlog2;

set_timeout();

my @data;
@data = split(/,/, $data) if $data;
push(@data, @ARGV);
@data || usage "no data set provided";
foreach(@data){
    vlog2 "data set: $_";
}
my $data_num = scalar @data;
($data_num < 1 ) && usage "No data sets provided";
vlog2 "\ntotal data sets: $data_num\n";

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
    vlog3 "$data2{$_} x data set: $_";
}
$msg2 =~ s/, $//;
if($ignore_nrpe_timeout){
    foreach(keys %data2){
        if(/^CHECK_NRPE: Socket timeout after \d+ seconds?\.?$/){
            vlog2 "ignoring nrpe timeout results";
            delete $data2{$_};
        }
    }
}
my $num_different_versions = keys %data2;
vlog2 "\ntotal different versions: $num_different_versions\n";

$status = "OK";
$msg = "$num_different_versions versions detected across cluster of $data_num (w=$warning/c=$critical) - $msg2";
check_thresholds($num_different_versions);
quit $status, $msg;
