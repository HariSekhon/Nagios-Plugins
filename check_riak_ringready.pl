#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 19:03:05 +0100 (Sun, 21 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Simple Nagios Plugin which calls 'riak-admin ringready' to check that all nodes agree on state

Useful to check that ring state has settled after changing cluster memberships

Designed to be run on a Riak node over NRPE

Tested on Riak 1.4.0, 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Riak;

%options = (
    %riak_admin_path_option,
);

get_options();

set_timeout();

get_riak_admin_path();

$status = "CRITICAL";

my $cmd = "riak-admin ringready";

vlog2 "running $cmd";
$msg = join(" ", cmd($cmd, 1));
vlog2 "checking $cmd results";

$msg =~ s/\s+/ /g;
$msg =~ s/, /,/;
$msg =~ /^TRUE/ and $status = "OK";
$msg =~ s/\[.*// unless $verbose;

vlog2;
quit $status, $msg;
