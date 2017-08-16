#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-26 20:05:04 +0100 (Sat, 26 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Simple Nagios Plugin to check 'riak-admin diag' for cluster health

Raises Critical or Warning if any such diagnostics are found, outputs the number of critical, warning and notice diagnostics

Designed to be run on each Riak node via NRPE

Tested on Riak 1.4.0, 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Riak;

my $cmd = "riak-admin diag";

my @diags = qw/critical warning notice/;
my %diags;
foreach(@diags){
    $diags{$_} = 0;
}

my $ignore_warnings;

%options = (
    %riak_admin_path_option,
    "ignore-warnings"   =>  [ \$ignore_warnings, "Ignore warnings and return OK, only raise alert on critical issues" ],
);
@usage_order = qw/riak-admin-path ignore-warnings/;

get_options();

set_timeout();

get_riak_admin_path();

$status = "OK";

vlog2 "running riak-admin diagnostics";
my @output = cmd($cmd, 1);
vlog2 "checking riak-admin diagnostic results";

foreach(@output){
    foreach my $status (@diags){
        if(/^\s*\[$status\]\s*/){
            $diags{$status}++;
            critical if $status eq "critical";
            warning  if $status eq "warning" and not $ignore_warnings;
            next;
        }
    }
}

$msg = "";
foreach(@diags){
    $msg .= "$diags{$_} $_, ";
}
$msg =~ s/, $//;

if($status ne "OK"){
    $msg .= ". Run with -vvv for full list of issues";
}

vlog2;
quit $status, $msg;
