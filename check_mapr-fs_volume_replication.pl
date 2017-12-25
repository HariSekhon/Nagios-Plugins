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

$DESCRIPTION = "Nagios Plugin to check MapR-FS replication for a given volume via the MapR Control System REST API

Checks thresholds as % at specified replication factor or higher (can be disabled to check this exact replication level). Perfdata is also output for graphing.

Tested on MapR 4.0.1, 5.1.0, 5.2.1";

$VERSION = "0.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::MapR;

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_threshold_defaults("95", "80");

my $replication_factor_min      = 0;
my $replication_factor_max      = 10;
my $replication_factor_default  = 3;
my $replication_factor          = $replication_factor_default;
my $no_higher_rep;

%options = (
    %mapr_options,
    %mapr_option_cluster,
    %mapr_option_volume,
    "R|replication-factor=s" => [ \$replication_factor, "Replication factor to expect and check threshold % against (default: $replication_factor_default)" ],
    "no-higher-repl"         => [ \$no_higher_rep,      "Don't count higher replication factors, match thresholds exactly against specified replication factor" ],
    %thresholdoptions,
);
splice @usage_order, 6, 0, qw/volume cluster replication-factor no-higher-repl list-volumes list-clusters/;

get_options();

validate_mapr_options();
list_clusters();
$cluster = validate_cluster($cluster) if $cluster;
list_volumes();
$volume  = validate_volume($volume);
isInt($replication_factor) or usage "replication factor is not an integer";
validate_int($replication_factor, "replication factor", $replication_factor_min, $replication_factor_max);
validate_thresholds(1, 1, { "simple" => "lower", "integer" => 0, "positive" => 1, "min" => 0, "max" => 100});

vlog2;
set_timeout();

$status = "OK";

my $url = "/volume/list";
$url .= "?" if ($cluster or $volume or not ($debug or $verbose > 3));
$url .= "cluster=$cluster&" if $cluster;
$url .= "filter=[volumename==$volume]&" if $volume;
$url .= "columns=volumename,mountdir,actualreplication" unless ($debug or $verbose > 3);
$url =~ s/&$//;

$json = curl_mapr $url, $user, $password;

my @data = get_field_array("data");

my %vols;
my $found = 0;
foreach(@data){
    my $vol = get_field2($_, "volumename");
    next if($volume and $volume ne $vol);
    $found++;
    # Information is not yet available for volume \'mapr.configuration\'. Please try again.
    my $actualreplication_tmp = get_field2_array($_, "actualreplication");
    if($actualreplication_tmp =~ /not yet available/){
        quit "UNKNOWN", "actualreplication field: $actualreplication_tmp";
    }
    @{$vols{$vol}{"rep"}} = get_field2_array($_, "actualreplication");
    $vols{$vol}{"mount"}  = get_field2($_, "mountdir");
}
if(not $found){
    if($volume){
        quit "UNKNOWN", "volume with name '$volume' was not found, check you've supplied the correct name, see --list-volumes";
    } else {
        quit "UNKNOWN", "no volumes found! See --list-volumes or -vvv. $nagios_plugins_support_msg_api";
    }
}

$msg .= "MapR-FS volume replication ";
foreach my $vol (sort keys %vols){
    $vols{$vol}{"total_min_rep"} = 0;
    my @rep = @{$vols{$vol}{"rep"}};
    for(my $rep = 0; $rep < scalar @rep; $rep++){
        if($rep >= $replication_factor){
            $vols{$vol}{"total_min_rep"} += $rep[$rep];
        }
        vlog2 "volume '$vol' ${rep}x or higher % = $vols{$vol}{total_min_rep}";
    }
}
foreach my $vol (sort keys %vols){
    $msg .= "'$vol'";
    $msg .= " ($vols{$vol}{mount})" if($verbose and $vols{$vol}{"mount"});
    my @rep = @{$vols{$vol}{"rep"}};
    for(my $rep = 0; $rep < scalar @rep; $rep++){
        if($rep[$rep] or $rep == $replication_factor){
            $msg .= " ${rep}x=$rep[$rep]%";
            if($rep == $replication_factor){
                if($no_higher_rep){
                    check_thresholds($rep[$rep]);
                } else {
                    check_thresholds($vols{$vol}{"total_min_rep"});
                }
            }
        }
    }
    $msg .= ", ";
}
$msg =~ s/, $//;
$msg .= " |";
foreach my $vol (sort keys %vols){
    my @rep = @{$vols{$vol}{"rep"}};
    for(my $rep = 0; $rep < scalar @rep; $rep++){
        $msg .= " 'volume $vol replication ${rep}x'=$rep[$rep]%";
        msg_perf_thresholds(0, "lower") if $rep == $replication_factor;
    }
}

vlog2;
quit $status, $msg;
