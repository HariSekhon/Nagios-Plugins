#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-03-01 19:03:41 +0000 (Sun, 01 Mar 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check Apache Drill metrics via the Rest API

Checks one or more given metrics. If none are specified returns all metrics.

Optional thresholds may be applied if a single metric is given.

Tested on Apache Drill 0.7, 0.8, 0.9, 1.0, 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 1.10, 1.11, 1.12, 1.13, 1.14, 1.15
";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use LWP::Simple '$ua';

set_port_default(8047);

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $metrics;

env_creds(["APACHE_DRILL", "DRILL"], "Apache Drill");

%options = (
    %hostoptions,
    "m|metrics=s"      => [ \$metrics,      "Metric(s) to fetch, comma separated (eg. gauges.heap.used,gauges.total.used,gauges.waiting.count ). Thresholds may optionally be applied if a single metric is given" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/metrics/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
my @metrics = validate_metrics($metrics);
validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

$json = curl_json "http://$host:$port/status/metrics";

# Pretty Print
if($verbose > 2){
    print Dumper($json);
    vlog2;
}

my %metrics = flattenStats($json);
vlog2;

$msg = "Apache Drill metrics:";
my $msg2;
my $value;

sub msg_metric($){
    my $key = shift;
    defined($metrics{$key}) or quit "UNKNOWN", "metric '$key' not found. Did you specify the correct metric key? Use -vv to see all metrics one per line";
    $value = $metrics{$key};
    $msg  .= " $key=$value";
    $msg2 .= " '$key'=$value";
}

if(scalar @metrics == 1){
    msg_metric($metrics[0]);
    check_thresholds($value);
} elsif(@metrics){
    foreach(@metrics){
        msg_metric($_);
    }
} else {
    foreach(sort keys %metrics){
        $msg .= " $_=$metrics{$_}";
        $msg2 .= " '$_'=$metrics{$_}";
    }
}
$msg .= " |$msg2";

quit $status, $msg;
