#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-26 20:05:04 +0100 (Sat, 26 Oct 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Simple Nagios Plugin to check 'riak-admin diag' for cluster health

Raises Critical or Warning if any such diagnostics are found, outputs the number of critical, warning and notice diagnostics

Designed to be run on each Riak node via NRPE

Tested on Riak 1.x, 2.0.0, 2.1.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

# This is the default install path for riak-admin from packages
$ENV{"PATH"} .= ":/usr/sbin";

my $path = "";

my $cmd = "riak-admin diag";

my @diags = qw/critical warning notice/;
my %diags;
foreach(@diags){
    $diags{$_} = 0;
}


%options = (
    "riak-admin-path=s"  => [ \$path, "Path to directory containing riak-admin command if differing from the default /usr/sbin" ],
);

get_options();

if($path){
    if(grep {$_ eq $path } split(":", $ENV{"PATH"})){
        usage "$path already in \$PATH ($ENV{PATH})";
    }
    $path = validate_directory($path, undef, "riak-admin PATH", "no vlog");
    $ENV{"PATH"} = "$path:$ENV{PATH}";
    vlog2 "\$PATH for riak-admin:",   $ENV{"PATH"};
    vlog2;
}

set_timeout();

$status = "OK";

vlog2 "running riak-admin diagnostics";
my @output = cmd($cmd, 1);
vlog2 "checking riak-admin diagnostic results";

foreach(@output){
    foreach my $status (@diags){
        if(/^\s*\[$status\]\s*/){
            $diags{$status}++;
            critical if $status eq "critical";
            warning  if $status eq "warning";
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
