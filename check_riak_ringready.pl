#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 19:03:05 +0100 (Sun, 21 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Simple Nagios Plugin which calls 'riak-admin ringready' to check that all nodes agree on state

Useful to check that ring state has settled after changing cluster memberships

Designed to be run on a Riak node over NRPE";

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

$status = "CRITICAL";

my $msg = join(" ", cmd("riak-admin ringready"));
$msg =~ s/\s+/ /g;
$msg =~ s/, /,/;
$msg =~ /^TRUE/ and $status = "OK";

quit $status, $msg;
