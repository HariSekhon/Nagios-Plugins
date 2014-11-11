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

$DESCRIPTION = "Nagios Plugin to check MapR-FS volume space used via the MapR Control System REST API

Can specify checking a single volume (returns all by default), and used space thresholds may be specified in MB. Perfdata is also output for graphing.

Tested on MapR 4.0.1";

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

my $logical_used;
my $list_volumes;
my $volume_name;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    "L|volume=s"      =>  [ \$volume_name,    "Volume name to check (returns all volumes by default)" ],
    "logical-used"    =>  [ \$logical_used,   "Check logical space used instead of total space used (ie excluded snapshots from the total)" ],
    "list-volumes"    =>  [ \$list_volumes,   "List volume names and mount points. Convenience switch to find what to supply to --volume" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/volume cluster logical-used list-volumes/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
if($volume_name){
    $volume_name =~ /^([A-Za-z0-9\._-]+)$/ or usage "invalid volume name specified";
    $volume_name = $1;
}
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/volume/list";
$url .= "?" if($cluster or ($volume_name and not $list_volumes));
$url .= "cluster=$cluster&" if $cluster;
if(not $list_volumes){
    $url .= "filter=[volumename==$volume_name]" if $volume_name;
}

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %vols;
my $found = 0;
foreach(@data){
    my $vol = get_field2($_, "volumename");
    unless($list_volumes){
        next if($volume_name and $volume_name ne $vol);
    }
    $found++;
    $vols{$vol}{"logicalUsed"} = get_field2($_, "logicalUsed");
    $vols{$vol}{"totalused"}   = get_field2($_, "totalused");
    $vols{$vol}{"mount"}       = get_field2($_, "mountdir");
    isFloat($vols{$vol}{"logicalUsed"}) or quit "UNKNOWN", "invalid non-float returned for logical used MB '$vols{$vol}{logicalUsed}' for volume '$vol' by MCS API. $nagios_plugins_support_msg_api";
    isFloat($vols{$vol}{"totalused"})   or quit "UNKNOWN", "invalid non-float returned for total used MB '$vols{$vol}{totalused}' for volume '$vol' by MCS API. $nagios_plugins_support_msg_api";
}
if($list_volumes){
    print "MapR-FS volumes:\n\n";
    printf("%-30s %s\n\n", "Name", "Mount Point");
    foreach my $vol (sort keys %vols){
        printf("%-30s %s\n", $vol, $vols{$vol}{"mount"});
    }
    exit $ERRORS{"UNKNOWN"};
} elsif(not $found){
    if($volume_name){
        quit "UNKNOWN", "volume with name '$volume_name' was not found, check you've supplied the correct name, see --list-volumes";
    } else {
        quit "UNKNOWN", "no volumes found! See --list-volumes or -vvv. $nagios_plugins_support_msg_api";
    }
}

plural keys %vols;
$msg .= "MapR-FS volume$plural space used ";
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{mount})" if($verbose and $vols{$vol}{"mount"});
    $msg .= " logical=" . human_units($vols{$vol}{logicalUsed}, "MB", 1);
    #$msg .= " logical=$vols{$vol}{logicalUsed}";
    check_thresholds($vols{$vol}{"logicalUsed"}) if $logical_used;
    $msg .= " total=" . human_units($vols{$vol}{totalused}, "MB", 1);
    $msg .= " total=$vols{$vol}{totalused}";
    check_thresholds($vols{$vol}{"totalused"}) unless $logical_used;
    $msg .= ", ";
}
$msg =~ s/, $//;
$msg .= " |";
foreach my $vol (sort keys %vols){
    $msg .= " 'volume $vol logical used'=$vols{$vol}{logicalUsed}MB";
    msg_perf_thresholds() if $logical_used;
    $msg .= " 'volume $vol total used'=$vols{$vol}{logicalUsed}MB";
    msg_perf_thresholds() unless $logical_used;
}

vlog2;
quit $status, $msg;
