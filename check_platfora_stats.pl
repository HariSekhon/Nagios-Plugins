#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-02 15:34:43 +0100 (Fri, 02 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check Platfora stats via the Rest API

Must check a single stat on each call due to the way the API is structured it might be too slow to issue multiple calls in a single plugin run.

Tested on Platfora 4.5.3";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
# seems to be a recent bug in IO::Socket::SSL not respecting $ua->ssl_opt(verify_hostname => 0)
# Net::SSL seems to ignore verification altogether - a potential hack workaround for now for self-signed certs like Platfora generates
#use Net::SSL;
use HariSekhonUtils;
use LWP::Simple '$ua';

set_port_default(8080);

env_creds("Platfora");

our $protocol = "http";
my $type;

# lensbuilds are not yet supported by the API when testing against Platfora 4.5.3
    #lensbuilds
my @valid_types = qw(
    users
    groups
    datasources
    datasets
    lenses
    vizboards
    workflows
    permissions
    renderjobs
);

%options = (
    %hostoptions,
    %useroptions,
    "T|type=s" => [ \$type, "Type of Platfora stat to query, Required, must be one of: " . join(", ", @valid_types) ],
    %ssloptions,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/type/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);

defined($type) or usage "--type not defined";
$type = lc $type;
grep { $_ eq $type } @valid_types or usage "invalid --type, must be one of the following valid types: " . join(", ", @valid_types);

validate_ssl();
validate_thresholds();

if($ssl and $port == 8080){
    vlog2 "\nchanging default port from 8080 to 8443 for SSL";
    $port = 8443;
}

vlog2;
set_timeout();

$status = "OK";

my $url = "$protocol://$host:$port/api/v1/$type?limit=1";

$json = curl_json $url, "Platfora", $user, $password;

my $count = get_field_int("_metadata.count");

$msg = "Platfora $type count = $count";
check_thresholds($count);
$msg .= " | '${type} count'=$count";
msg_perf_thresholds();

quit $status, $msg;
