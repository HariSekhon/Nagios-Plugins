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

$DESCRIPTION = "Nagios Plugin to check MapR-FS volumes are mounted, not read-only and not in need of Gfsck via the MapR Control System REST API

Can specify a single volume to check, by default checks all volumes.

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

my $ignore_mounted;
my $ignore_readonly;
my $ignore_needsGfsck;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    "L|volume=s"         =>  [ \$volume_name,       "Volume name to check (returns all volumes by default)" ],
    "logical-used"       =>  [ \$logical_used,      "Check logical space used instead of total space used (ie excluded snapshots from the total)" ],
    "list-volumes"       =>  [ \$list_volumes,      "List volume names and mount points. Convenience switch to find what to supply to --volume" ],
    "ignore-mounted"     =>  [ \$ignore_mounted,    "Ignore mounted" ],
    "ignore-readonly"    =>  [ \$ignore_mounted,    "Ignore read only" ],
    "ignore-needsGfsck"  =>  [ \$ignore_needsGfsck, "Ignore needs Gfsck" ],
);
splice @usage_order, 6, 0, qw/volume cluster ignore-mounted ignore-readonly ignore-needsGfsck list-volumes/;

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

my $url = "/volume/list?";
$url .= "cluster=$cluster&" if $cluster;
if(not $list_volumes){
    $url .= "filter=[volumename==$volume_name]&" if $volume_name;
}
$url .= "columns=volumename,mountdir,readonly,needsGfsck,mounted";

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
    $vols{$vol}{"mount"}       = get_field2($_, "mountdir");
    $vols{$vol}{"mounted"}     = get_field2($_, "mounted");
    $vols{$vol}{"needsGfsck"}  = get_field2($_, "needsGfsck");
    $vols{$vol}{"readonly"}    = get_field2($_, "readonly");
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

# Logical for alering and CAPITALIZING what is generating the alert status
foreach my $vol (keys %vols){
    if($vols{$vol}{"mounted"}){
        $vols{$vol}{"mounted"} = "true";
    } elsif($ignore_mounted){
        $vols{$vol}{"mounted"} = "false";
    } elsif(grep { $vol eq $_ } qw/mapr.cldb.internal/){
        $vols{$vol}{"mounted"} = "false";
    } else {
        critical;
        $vols{$vol}{"mounted"} = "FALSE";
    }

    if($vols{$vol}{"needsGfsck"}){
        if($ignore_needsGfsck){
            $vols{$vol}{"needsGfsck"} = "true";
        } else {
            critical;
            $vols{$vol}{"needsGfsck"} = "TRUE";
        }
    } else {
        $vols{$vol}{"needsGfsck"} = "false";
    }

    if($vols{$vol}{"readonly"}){
        if($ignore_readonly){
            $vols{$vol}{"readonly"} = "true";
        } else {
            critical;
            $vols{$vol}{"readonly"} = "TRUE";
        }
    } else {
        $vols{$vol}{"readonly"} = "false";
    }
}

plural keys %vols;
$msg .= "MapR-FS volume$plural ";
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{mount})" if($verbose and $vols{$vol}{"mount"});
    $msg .= " mounted=$vols{$vol}{mounted}";
    $msg .= " readonly=$vols{$vol}{readonly}";
    $msg .= " needsGfsck=$vols{$vol}{needsGfsck}";
    $msg .= ", ";
}
$msg =~ s/, $//;

vlog2;
quit $status, $msg;
