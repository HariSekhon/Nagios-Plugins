#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-11 20:11:15 +0100 (Fri, 11 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# still calling v1 for compatability with older CM versions
#
# http://cloudera.github.io/cm_api/apidocs/v1/index.html

$DESCRIPTION = "Nagios Plugin to check given CDH Hadoop cluster major release version via Cloudera Manager Rest API

You may need to upgrade to Cloudera Manager 4.6 for the Standard Edition (free) to allow the API to be used, but it should work on all versions of Cloudera Manager Enterprise Edition

This is still using v1 of the API for compatability purposes

Tested on Cloudera Manager 5.0.0, 5.7.0, 5.10.0, 5.12.0 with CDH 4.6 and CDH 5.x clusters";

$VERSION = "0.2.0";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::ClouderaManager;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $expected;

%options = (
    %hostoptions,
    %useroptions,
    %cm_option_cluster,
    "list-clusters" =>  $cm_options_list{"list-clusters"},
    %cm_options_tls,
    "e|expected=s"  =>  [ \$expected, "Expected cluster version regex (optional)" ],
);

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

validate_regex($expected) if defined($expected);

validate_thresholds();

vlog2;
set_timeout();

$status = "OK";

list_cm_components();

$cluster = validate_cm_cluster();
$url = "$api/clusters/$cluster";
cm_query();
my $version = get_field("fullVersion");
$msg = "cluster '$cluster' version '$version'";
if(defined($expected)){
    unless($version =~ /^$expected/){
        critical;
        $msg .= " (expected: '$expected')";
    }
}

quit $status, $msg;
