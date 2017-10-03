#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-02 16:52:08 +0100 (Fri, 02 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check Ranger stats for number of policies and repositories via the Rest API

If isolating to one type then optional thresholds may be applied.

Tested on Hortonworks HDP 2.3 (Ranger 0.5) and HDP 2.6.1 (Ranger 0.7)";

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

set_port_default(6080);

env_creds("Ranger");

our $protocol = "http";
my $type;
my @valid_types = qw/policy repository/;

%options = (
    %hostoptions,
    %useroptions,
    "T|type=s" => [ \$type, "Stat to query, Optional, can be one of (otherwise queries all of): " . join(", ", @valid_types) ],
    #%ssloptions,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/type/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

if(defined($type)){
    $type = lc $type;
    grep { $_ eq $type } @valid_types or usage "invalid --type, must be one of the following valid types: " . join(", ", @valid_types);
}

validate_ssl();
validate_thresholds() if $type;

vlog2;
set_timeout();

$status = "OK";

my $url = "$protocol://$host:$port/service/public/api";

my @types = @valid_types;
@types = $type if(defined($type));
my $count;
my $msg2;

foreach my $type (@types){
    $json = curl_json "$url/$type", "Ranger", $user, $password;
    vlog3 Dumper($json);
    $count = get_field_int("totalCount");
    $msg .= ", $type count = $count";
    check_thresholds($count);
    $msg2 .= " '${type} count'=$count";
    $msg2 .= msg_perf_thresholds(1);
}
$msg =~ s/^, //;

$msg = "Ranger $msg |$msg2";

vlog2;
quit $status, $msg;
