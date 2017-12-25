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

$DESCRIPTION = "Nagios Plugin to check MapR-FS snapshots for a given volume via the MapR Control System REST API

Checks:

- there is at least one snapshot
- minimum number of snapshots (--min-snapshots, raises warning, optional)
- most recent snapshot occurred within the last x minutes (--warning/critical thresholds, optional)
- perfdata is also output for graphing

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
use Time::Local;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $min_snaps = 1;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_volume,
    "min-snapshots=s"   => [ \$min_snaps, "Minimum number of snapshots to expect (raises warning if below this number, or critical if zero)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/volume cluster min-snapshots list-volumes list-clusters/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
list_volumes();
$volume  = validate_volume($volume);
validate_int($min_snaps, "minimum snapshots", 1, 1000000);
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 0, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/volume/snapshot/list";
$url .= "?" if ($cluster or $volume or not ($debug or $verbose > 3));
$url .= "cluster=$cluster&" if $cluster;
$url .= "filter=[volumename==$volume]&" if $volume;
# TODO: check snapshotused vs cumulativeReclaimSizeMB, and snapshotcount
# dsu field was documented but not found in MapR 4.0.1's API, found cumulativeReclaimSizeMB instead
$url .= "columns=volumename,volumepath,snapshotname,cumulativeReclaimSizeMB,creationtime,expirytime" unless ($debug or $verbose > 3);
$url =~ s/&$//;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %vols;
my $num_snaps = 0;
foreach(@data){
    my $vol = get_field2($_, "volumename");
    next if($volume and $volume ne $vol);
    $num_snaps++;
    $vols{$vol}{"creationtime"} = get_field2($_, "creationtime");
    $vols{$vol}{"creationtime"} =~ /^\w+\s+([A-Za-z]{3})\s+(\d{1,2})\s+(\d{1,2}):(\d{2}):(\d{2})\s+(\w+)\s+(\d{4})$/ or quit "UNKNOWN", "failed to parse creationtime. $nagios_plugins_support_msg_api";
    my $age_secs = 0;
    if($6 eq "GMT"){
        $age_secs = time - timegm($5, $4, $3, $2, month2int($1), $7);
    } else {
        $age_secs = time - timelocal($5, $4, $3, $2, month2int($1), $7);
    }
    if($age_secs < 0) {
        quit "UNKNOWN", "snapshot time is in the future, NTP issue between hosts?";
    }
    if(not defined($vols{$vol}{"age_secs"}) or $age_secs < $vols{$vol}{"age_secs"}){
        $vols{$vol}{"expirytime"}   = get_field2($_, "expirytime", "optional");
        $vols{$vol}{"cumulativeReclaimSizeMB"} = get_field2_int($_, "cumulativeReclaimSizeMB");
        $vols{$vol}{"snapshotname"} = get_field2($_, "snapshotname");
        $vols{$vol}{"volumepath"}   = get_field2($_, "volumepath");
        $vols{$vol}{"age_secs"} = $age_secs;
        $vols{$vol}{"age_mins"} = sprintf("%.1f", $age_secs / 60);
    }
}
$num_snaps or quit "UNKNOWN", "no MapR-FS snapshots found for volume '$volume'!"; # See --list-volumes or -vvv. $nagios_plugins_support_msg_api";

plural $num_snaps;
$msg .= "MapR-FS has $num_snaps snapshot$plural";
if($num_snaps < $min_snaps){
    warning;
    $msg .= " (< minimum $min_snaps)";
} elsif($verbose){
    $msg .= " (minimum $min_snaps)";
}
$msg .= " for volume ";
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{volumepath})" if($verbose and $vols{$vol}{"volumepath"});
    $msg .= ", most recent $vols{$vol}{age_mins} mins ago";
    check_thresholds($vols{$vol}{"age_mins"});
    $msg .= ", used=" . human_units($vols{$vol}{"cumulativeReclaimSizeMB"}, "MB", "terse");
    $msg .= ", creationtime='$vols{$vol}{creationtime}'";
    $msg .= ", expirytime='$vols{$vol}{expirytime}'" if ($verbose and $vols{$vol}{"expirytime"});
    $msg .= ", ";
}
$msg =~ s/, $//;
$msg .= " |";
foreach my $vol (sort keys %vols){
    $msg .= " 'volume $vol number of snapshots'=$num_snaps;$min_snaps 'volume $vol latest snapshot age (mins)'=$vols{$vol}{age_mins}";
    msg_perf_thresholds();
    $msg .= " 'volume $vol latest snapshot cumulativeReclaimSize'=$vols{$vol}{cumulativeReclaimSizeMB}MB";
}

vlog2;
quit $status, $msg;
