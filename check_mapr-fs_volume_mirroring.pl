#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-11-11 19:30:38 +0000 (Tue, 11 Nov 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check MapR-FS mirroring for a given volume via the MapR Control System REST API

Checks optional thresholds as % mirroring complete (latest run). If checking % complete would be best to do so on a schedule (eg. 9am every day check mirror is 100%). Perfdata is also output for graphing.

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_volume,
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/volume cluster list-volumes list-clusters/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
list_volumes();
$volume  = validate_volume($volume);
validate_thresholds(0, 0, { "simple" => "lower", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100});

vlog2;
set_timeout();

$status = "OK";

my $url = "/volume/list";
$url .= "?" if ($cluster or $volume or not ($debug or $verbose > 3));
$url .= "cluster=$cluster&" if $cluster;
$url .= "filter=[volumename==$volume]&" if $volume;
$url .= "columns=volumename,mountdir,mirror-percent-complete" unless ($debug or $verbose > 3);
$url =~ s/&$//;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %vols;
my $found = 0;
foreach(@data){
    my $vol = get_field2($_, "volumename");
    next if($volume and $volume ne $vol);
    $found++;
    $vols{$vol}{"mirror"} = get_field2($_, "mirror-percent-complete");
    $vols{$vol}{"mount"}  = get_field2($_, "mountdir");
}
if(not $found){
    if($volume){
        quit "UNKNOWN", "volume with name '$volume' was not found, check you've supplied the correct name, see --list-volumes";
    } else {
        quit "UNKNOWN", "no volumes found! See --list-volumes or -vvv. $nagios_plugins_support_msg_api";
    }
}

plural keys %vols;
$msg .= "MapR-FS volume$plural ";
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{mount})" if($verbose and $vols{$vol}{"mount"});
    $msg .= " mirror=$vols{$vol}{mirror}%";
    check_thresholds($vols{$vol}{"mirror"});
    $msg .= ", ";
}
$msg =~ s/, $//;
$msg .= " |";
foreach my $vol (sort keys %vols){
    $msg .= " 'volume $vol mirror'=$vols{$vol}{mirror}%";
    msg_perf_thresholds(0, "lower");
}

vlog2;
quit $status, $msg;
