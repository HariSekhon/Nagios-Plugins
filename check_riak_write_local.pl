#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-06-13 22:36:30 +0100 (Sat, 13 Jun 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check a Riak read/write cycle via riak-admin test

Designed to be run on a Riak node via NRPE

See also check_riak_write.pl which runs remotely via API and outputs read/write/delete timing stats

Tested on Riak 2.0.0, 2.1.1, 2.1.4";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::Riak;

my $cmd = "riak-admin test";

%options = (
    %riak_admin_path_option,
);

get_options();

set_timeout();

$status = "OK";

vlog2 "running $cmd";
$msg = join(" ", cmd($cmd, 1));
vlog2 "checking $cmd results";

$msg =~ /^Successfully/ or critical;
$msg =~ s/ to '[^']+'\s*$//g unless $verbose;

vlog2;
quit $status, $msg;
