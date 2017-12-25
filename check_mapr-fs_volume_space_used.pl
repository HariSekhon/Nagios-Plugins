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

my $logical_used;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_volume,
    "logical-used"    =>  [ \$logical_used,   "Check logical space used instead of total space used (ie uncompressed data size instead of actual disk used)" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/volume cluster logical-used list-volumes list-clusters/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
list_volumes();
$volume = validate_volume($volume) if $volume;
validate_thresholds(0, 0, { "simple" => "upper", "integer" => 1, "positive" => 1});

vlog2;
set_timeout();

$status = "OK";

my $url = "/volume/list";
$url .= "?" if($cluster or $volume);
$url .= "cluster=$cluster&" if $cluster;
$url .= "filter=[volumename==$volume]&" if $volume;
$url .= "columns=volumename,mountdir,logicalUsed,totalused" unless ($debug or $verbose > 3);
$url =~ s/&$//;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %vols;
my $found = 0;
foreach(@data){
    my $vol = get_field2($_, "volumename");
    next if($volume and $volume ne $vol);
    $found++;
    $vols{$vol}{"logicalUsed"} = get_field2($_, "logicalUsed");
    $vols{$vol}{"totalused"}   = get_field2($_, "totalused");
    $vols{$vol}{"mount"}       = get_field2($_, "mountdir");
    isFloat($vols{$vol}{"logicalUsed"}) or quit "UNKNOWN", "invalid non-float returned for logical used MB '$vols{$vol}{logicalUsed}' for volume '$vol' by MCS API. $nagios_plugins_support_msg_api";
    isFloat($vols{$vol}{"totalused"})   or quit "UNKNOWN", "invalid non-float returned for total used MB '$vols{$vol}{totalused}' for volume '$vol' by MCS API. $nagios_plugins_support_msg_api";
}
if(not $found){
    if($volume){
        quit "UNKNOWN", "volume with name '$volume' was not found, check you've supplied the correct name, see --list-volumes";
    } else {
        quit "UNKNOWN", "no volumes found! See --list-volumes or -vvv. $nagios_plugins_support_msg_api";
    }
}

plural keys %vols;
$msg .= "MapR-FS volume$plural space used: ";
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{mount})" if($verbose and $vols{$vol}{"mount"});
    $msg .= " logical=" . human_units($vols{$vol}{logicalUsed}, "MB", 1);
    #$msg .= " logical=$vols{$vol}{logicalUsed}";
    check_thresholds($vols{$vol}{"logicalUsed"}) if $logical_used;
    $msg .= " total=" . human_units($vols{$vol}{totalused}, "MB", 1);
    #$msg .= " total=$vols{$vol}{totalused}";
    check_thresholds($vols{$vol}{"totalused"}) unless $logical_used;
    $msg .= ", ";
}
$msg =~ s/, $//;
$msg .= " |";
foreach my $vol (sort keys %vols){
    $msg .= " 'volume $vol logical used'=$vols{$vol}{logicalUsed}MB";
    msg_perf_thresholds() if $logical_used;
    $msg .= " 'volume $vol total used'=$vols{$vol}{totalused}MB";
    msg_perf_thresholds() unless $logical_used;
}

vlog2;
quit $status, $msg;
