#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date:   2014-02-19 22:00:59 +0000 (Wed, 19 Feb 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  vim:ts=4:sts=4:sw=4:et

$DESCRIPTION = "Nagios Plugin to check MapR-FS disk status and space used % for a given MapR node via the MapR Control System REST API

(MapR-FS disk status and space isn't visible from Linux as MapR-FS uses raw devices, so check_disk can't be used with MapR-FS disks)

Can optionally have it check --all-disks and not just MapR-FS disks.

Checks:

- raises critical if any of the checked disks have bad operational status
  - outputs operational status after each disk label in verbose mode
- reports disk used % for each disk as well as used/total figures
- checks warning/critical thresholds against the percentage of used space on each disk where applicable
- outputs each disk's power status in verbose mode or if it isn't 'running' or 'Active/idle'

LVM disks and similar won't show used space as MapR doesn't understand those raw devices, so /dev/dm-* will only show total space for those partitions, but will still check their status is 'ok' and raise alert otherwise.

Tested on MapR 3.1.0, 4.0.1, 5.1.0, 5.2.1";

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

set_threshold_defaults(80, 95);

my %powerstatus = (
    0 => "Active/idle",
    1 => "Standby",
    2 => "Sleeping",
);

my $all_disks;

%options = (
    %mapr_options,
    %mapr_option_node,
    "A|all-disks" => [ \$all_disks,   "Check all disks and not just MapR-FS disks" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/node all-disks list-nodes ssl ssl-CA-path ssl-noverify no-ssl/;

get_options();

validate_mapr_options();
list_nodes();
$node = validate_host($node, "node");
validate_thresholds(1, 1, { "simple" => "upper", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100});

vlog2;
set_timeout();

$status = "OK";

my $url = "/disk/list?host=$node" . ( $all_disks ? "" : "&system=0" );

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

quit "UNKNOWN", "no disk data returned for node '$node'" unless @data;

my %disks;

sub get_disk_info($){
    my $disk_hash_ref = shift;
    my $diskname                        = get_field2($disk_hash_ref, "diskname");
    grep { $_ eq $diskname } keys %disks and quit "UNKNOWN", "duplicate disk names '$diskname' detected. $nagios_plugins_support_msg_api";
    #$disks{$diskname}{"availablespace"} = get_field2($disk_hash_ref, "availablespace");
    $disks{$diskname}{"powerstatus"}    = get_field2($disk_hash_ref, "powerstatus", "noquit");
    $disks{$diskname}{"status"}         = get_field2($disk_hash_ref, "status");
    $disks{$diskname}{"totalspace"}     = get_field2($disk_hash_ref, "totalspace");
    $disks{$diskname}{"usedspace"}      = get_field2($disk_hash_ref, "usedspace", "noquit");
    if(defined($disks{$diskname}{"usedspace"})){
        $disks{$diskname}{"used_pc"}    = $disks{$diskname}{"usedspace"} / $disks{$diskname}{"totalspace"} * 100;
    }
    if($disks{$diskname}{"status"} eq 0){
        $disks{$diskname}{"status"} = "ok";
    } else {
        critical;
        $disks{$diskname}{"status"} = "BAD";
    }
    if(defined($disks{$diskname}{"powerstatus"}) and grep { $disks{$diskname}{"powerstatus"} eq $_ } keys %powerstatus){
        $disks{$diskname}{"powerstatus"} = $powerstatus{$disks{$diskname}{"powerstatus"}};
    }
}

my $fstype;
foreach(@data){
    $fstype = get_field2($_, "fstype", "noquit");
    if($all_disks){
        get_disk_info($_);
    } elsif(defined($fstype) and $fstype eq "MapR-FS"){
        get_disk_info($_);
    }
}

if($all_disks){
    $msg .= "all";
} else {
    $msg .= "MapR-FS";
}
$msg .= " disks: ";
my $msg2;
foreach my $diskname (sort keys %disks){
    $msg .= "$diskname ";
    if($verbose or $disks{$diskname}{"status"} ne "ok"){
        $msg .= "$disks{$diskname}{status} ";
    }
    if(defined($disks{$diskname}{"used_pc"})){
        defined($disks{$diskname}{"usedspace"}) or code_error "disk used_pc defined but usedspace not defined";
        $msg .= sprintf("%.2f%%", $disks{$diskname}{"used_pc"});
        check_thresholds($disks{$diskname}{"used_pc"});
        $msg .= sprintf(" [%s/%s", human_units(expand_units($disks{$diskname}{"usedspace"}, "MB")), human_units(expand_units($disks{$diskname}{"totalspace"}, "MB")));
        $msg2 .= sprintf("'%s used space %%'=%.2f%%%s '%s used space'=%dMB ", $diskname, $disks{$diskname}{"used_pc"},  msg_perf_thresholds(1), $diskname, $disks{$diskname}{"usedspace"});
    } else {
        $msg .= sprintf("[%s", human_units(expand_units($disks{$diskname}{"totalspace"}, "MB")));
    }
    if( defined($disks{$diskname}{"powerstatus"}) and
        ( $verbose or
            ( $disks{$diskname}{"powerstatus"} ne "running" and $disks{$diskname}{"powerstatus"} ne "Active/idle")
        )
      ){
        $msg .= ", $disks{$diskname}{powerstatus}"
    }
    $msg .= "], ";
}
$msg =~ s/, $//;
$msg .= " | $msg2";

vlog2;
quit $status, $msg;
