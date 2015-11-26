#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-18 18:44:35 +0100 (Fri, 18 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www.datastax.com/documentation/opscenter/5.0/api/docs/backups.html#backups

$DESCRIPTION = "Nagios Plugin to check DataStax OpsCenter backups for a given cluster/keyspace via the DataStax OpsCenter Rest API

Requires DataStax Enterprise

Tested on DataStax OpsCenter 5.0.0 with DataStax Enterprise Server 4.5.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::DataStax::OpsCenter;
use Data::Dumper;
use LWP::Simple '$ua';
use POSIX 'strftime';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $min_backups = 1;
my $max_age;

%options = (
    %hostoptions,
    %useroptions,
    %clusteroption,
    %keyspaceoption,
    "min-backups=s"  =>  [ \$min_backups,    "Minimum number of backups to expect (default: 1)" ],
    "max-age=s"      =>  [ \$max_age,        "Max time in secs since last backup (optional)" ],
);
splice @usage_order, 6, 0, qw/cluster keyspace min-backups max-age list-clusters list-keyspaces/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_cluster();
$keyspace    = validate_keyspace() if $keyspace;
$min_backups = validate_int($min_backups, "min backups", 0);
$max_age     = validate_int($max_age,  "max backup age",  0) if defined($max_age);

vlog2;
set_timeout();
set_http_timeout($timeout-1);

$ua->show_progress(1) if $debug;

$status = "OK";

list_clusters();
list_keyspaces();

my $url;
if($keyspace) {
    $url = "$cluster/backups/$keyspace";
} else {
    $url = "$cluster/backups";
}

$json = curl_opscenter $url;
vlog3 Dumper($json);

isHash($json) or quit "UNKNOWN", "non-hash returned. $nagios_plugins_support_msg_api";

my $num_backups = scalar keys %{$json};
plural $num_backups;
$msg = "$num_backups backup$plural found in DataStax OpsCenter for cluster '$cluster'";
$msg .= " keyspace '$keyspace'" if $keyspace;
if($num_backups < $min_backups){
    critical;
    plural $min_backups;
    $msg .= " (expected minimum of $min_backups backup$plural)";
}
if($num_backups > 0){
    # find timestamp of last backup and use that
    my $last_timestamp = 0;
    my $this_timestamp;
    foreach(sort keys %{$json}){
        $this_timestamp = get_field("$_.time");
        if($this_timestamp > $last_timestamp){
            $last_timestamp = $this_timestamp;
        }
    }
    # OpsCenter displays this in gmtime so we will too
    $msg .= ", last backup was '" . strftime("%F %T", gmtime($last_timestamp)) . "' GMT";
    my $age = time - $last_timestamp;
    $msg .= " ($age secs ago";
    if($age < 0){
        unknown;
        $msg .= " - NTP mismatch between hosts?";
    } else {
        if($max_age and $age > $max_age){
            critical;
            $msg .= " > max age $max_age secs";
        }
    }
    $msg .= ")";
}

vlog2;
quit $status, $msg;
