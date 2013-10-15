#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-06-17 15:03:12 +0100 (Fri, 17 Jun 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to test a Linux Interface for errors, promisc mode etc, designed to be run locally on machine over NRPE or similar";

$VERSION = "0.8.8";

use strict;
use warnings;
use Sys::Hostname;
use Fcntl ':flock';
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $errors = 0;
my $ethtool  = "/sbin/ethtool";
my $expected_duplex;
my $expected_speed;
my $expected_mtu;
my $expected_promisc = "off";
# could use /proc/net/dev but this is easier
my $ifconfig = "/sbin/ifconfig";
my $interface;
my $promisc = "off";
my $short = 0;

%options = (
    "i|interface=s" => [ \$interface,           "Interface to check (eg. eth0, eth1, bond0 etc)" ],
    "e|errors"      => [ \$errors,              "Go critical on any interface errors, collisions, interface resets etc" ],
    "d|duplex=s"    => [ \$expected_duplex,     "Specify duplex to expect on interface. If specified, must be one of: Full/Half" ],
    "s|speed=i"     => [ \$expected_speed,      "Specify speed  to expect on interface. If specified, must be one of: 10/100/1000/10000" ],
    "m|mtu=i"       => [ \$expected_mtu,        "Specify an MTU to expect on interface. If specified, must be 1-4 digits long" ],
    "p|promisc=s"   => [ \$expected_promisc,    "Specify whether promiscuous mode is on or off. If specified, arg must be one of: on/off (default: off)" ],
    "short"         => [ \$short,               "Shorten output, do not print expected values when there is a mismatch" ],
);
@usage_order = qw(interface errors duplex speed mtu promisc short);

get_options();

$interface = validate_interface($interface);
my $bond = $interface =~ /^bond\d+$/;

if(defined($expected_duplex)){
    $expected_duplex = ucfirst lc $expected_duplex;
    $expected_duplex =~ /^(Full|Half)$/ or usage "invalid duplex specified, must be either Full or Half";
    $expected_duplex = $1;
    vlog_options "expected duplex", $expected_duplex;
}

if(defined($expected_speed)){
    $expected_speed =~ /^(10{1,4})$/ or usage "invalid speed specified, must be one of: 10/100/1000/10000";
    $expected_speed = $1;
    vlog_options "expected speed", $expected_speed;
}

if(defined($expected_mtu)){
    $expected_mtu =~ /^(\d{1,4})$/ or usage "invalid mtu specified, must be 1-4 digits";
    $expected_mtu = $1;
    vlog_options "expected mtu", $expected_mtu;
}

if(defined($expected_promisc)){
    # lc $expected_promisc;
    $expected_promisc =~ /^(on|off)$/ or usage "promiscuous mode must be either set to either 'on' or 'off'";
    $expected_promisc = $1;
    vlog_options "expected promiscuous mode", $expected_promisc;
}
vlog2;

linux_only();

set_timeout();

which($ifconfig, 1);

my $cmd = "$ifconfig 2>&1";
my $found_interface = 0;
my ( $encap, $mac );
$status = "OK";

my %stats;
my $mtu;

vlog2 "cmd: $cmd\n";
open my $fh, "$ifconfig -a 2>&1 |" or quit "UNKNOWN", "failed to run '$ifconfig': $!";
while(<$fh>){
    chomp;
    vlog3 "$_";
    next until /^$interface\s+Link encap:(\w+)\s+HWaddr ((?:[A-Fa-f0-9]{2}:){5}(?:[A-Fa-f0-9]{2}))\s*$/;
    $encap = $1;
    $mac   = $2;
    $found_interface = 1;
    last;
}
( $found_interface eq 1 ) or quit "UNKNOWN", "can't find interface '$interface' in output from '$ifconfig' command";
defined($mac) or quit "UNKNOWN", "can't find MAC address for interface '$interface' in output from '$ifconfig' command";
( $encap eq "Ethernet" ) or $msg .= "Encapsulation is '$encap', not Ethernet! ";
vlog3 "\n$interface Encapsulation: $encap";
vlog3 "$interface MAC: $mac\n";
vlog3 "ifconfig output for $interface:\n";
while(<$fh>){
    chomp;
    vlog3 "$_";
    if(/\s+MTU:(\d+)\s+/){
        $mtu = $1;
        # NOTE: due to kernel changes ifconfig doesn't report this correctly unless it has set it itself, check further down for a fix
        if (/PROMISC/){
            $promisc = "on";
            warning;
        }
    } elsif(/^\s+RX packets:(\d+) errors:(\d+) dropped:(\d+) overruns:(\d+) frame:(\d+)\s*$/){
        $stats{"RX_packets"}  = $1;
        $stats{"RX_errors"}   = $2;
        $stats{"RX_dropped"}  = $3;
        $stats{"RX_overruns"} = $4;
        $stats{"RX_frame"}    = $5;
    } elsif(/^\s+TX packets:(\d+) errors:(\d+) dropped:(\d+) overruns:(\d+) carrier:(\d+)\s*$/){
        $stats{"TX_packets"}  = $1;
        $stats{"TX_errors"}   = $2;
        $stats{"TX_dropped"}  = $3;
        $stats{"TX_overruns"} = $4;
        $stats{"TX_carrier"}  = $5;
    } elsif(/^\s+collisions:(\d+) txqueuelen:(\d+)\s*$/){
        $stats{"collisions"}  = $1;
        #$stats{"txqueuelen"}  = $2;
    } elsif(/^\s+RX bytes:(\d+) \(.+\)\s+TX bytes:(\d+) \(.+\)\s*$/){
        $stats{"RX_bytes"}    = $1;
        $stats{"TX_bytes"}    = $2;
    } elsif(/^\s+Interrupt:(\d+)\s+/){
        $stats{"interrupts"}  = $1;
    }
    last if /^\s*$/;
}
close $fh;

# PROMISC fix:
my $int_flags_fh = open_file("/sys/class/net/$interface/flags");
my $int_flags = <$int_flags_fh>;
chomp $int_flags;
$int_flags = scalar trim($int_flags);
isHex($int_flags) or quit "UNKNOWN", "failed to get hex flags from /sys/class/net/$interface/flags (got '$int_flags', failed regex validation)"; 
if((hex $int_flags) & 0x100){
    $promisc = "on";
    warning;
}

unless($mtu){
    quit "UNKNOWN", "could not find MTU in output from '$ifconfig'";
}
unless($mtu =~ /^\d+$/){
    quit "UNKNOWN", "invalid non-digit value found for MTU in output from '$ifconfig'";
}
# Not checking for interrupts as they are not present on bond interfaces or in VMs
foreach(qw/RX_packets RX_errors RX_dropped RX_overruns RX_frame TX_packets TX_errors TX_dropped TX_overruns TX_carrier collisions interrupts/){
    if($_ eq "interrupts" and !defined($stats{"interrupts"})){ $stats{"interrupts"} = "N/A"; next; }
    defined($stats{$_})     or quit "UNKNOWN", "could not find $_ in output from '$ifconfig'";
    ($stats{$_} =~ /^\d+$/) or quit "UNKNOWN", "invalid non-digit value found for $_ in output from '$ifconfig'";
}

# TODO: I use this paradigm quite a bit, unify it in my personal lib
my $tmpfh;
my $statefile = "/tmp/$progname.$interface.state";
my $statefile_found = ( -f $statefile );
if($statefile_found){
    vlog2 "opening state file '$statefile'\n";
    open $tmpfh, "+<$statefile" or quit "UNKNOWN", "Error: failed to open state file '$statefile': $!";
} else {
    vlog2 "creating state file '$statefile'\n";
    open $tmpfh, "+>$statefile" or quit "UNKNOWN", "Error: failed to create state file '$statefile': $!";
}
flock($tmpfh, LOCK_EX | LOCK_NB) or quit "UNKNOWN", "Failed to aquire a lock on state file '$statefile', another instance of this plugin was running?";
my $last_line = <$tmpfh>;
my $now = time;
my $last_timestamp;
my %last_stats = (
    "RX_packets"  => "",
    "TX_packets"  => "",
    "RX_bytes"    => "",
    "TX_bytes"    => "",
);
my @error_stats = (qw/RX_errors RX_dropped RX_overruns RX_frame TX_errors TX_dropped TX_overruns TX_carrier collisions interrupts/);
if($last_line){
    vlog2 "last line of state file: <$last_line>\n";
    if($last_line =~ /^(\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+)\s+
                       (\d+|N\/A)\s*$/x){
        $last_timestamp            = $1;
        $last_stats{"RX_packets"}  = $2;
        $last_stats{"RX_errors"}   = $3;
        $last_stats{"RX_dropped"}  = $4;
        $last_stats{"RX_overruns"} = $5;
        $last_stats{"RX_frame"}    = $6;
        $last_stats{"TX_packets"}  = $7;
        $last_stats{"TX_errors"}   = $8;
        $last_stats{"TX_dropped"}  = $9;
        $last_stats{"TX_overruns"} = $10;
        $last_stats{"TX_carrier"}  = $11;
        $last_stats{"collisions"}  = $12;
        $last_stats{"RX_bytes"}    = $13;
        $last_stats{"TX_bytes"}    = $14;
        $last_stats{"interrupts"}  = $15;
    } else {
        vlog2 "state file contents didn't match expected format\n";
    }
} else {
    vlog2 "no state file contents found\n";
}
my $stats_missing = 0;
foreach(keys %last_stats){
    unless($last_stats{$_} =~ /^\d+$/){
        next if ($_ eq "interrupts" and $last_stats{$_} =~ /^N\/A$/);
        vlog2 "'$_' stat was not found in state file" if $statefile_found;
        $stats_missing = 1;
        last;
    }
}

if(not $last_timestamp or $stats_missing){
        vlog2 "missing or incorrect stats in state file, resetting to current values\n" if $statefile_found;
        $last_timestamp = $now;
}
seek($tmpfh, 0, 0)  or quit "UNKNOWN", "Error: seek failed on state file '$statefile': $!\n";
truncate($tmpfh, 0) or quit "UNKNOWN", "Error: failed to truncate state file '$statefile': $!";
print $tmpfh "$now ";
foreach(qw/RX_packets RX_errors RX_dropped RX_overruns RX_frame TX_packets TX_errors TX_dropped TX_overruns TX_carrier collisions RX_bytes TX_bytes interrupts/){
    print $tmpfh "$stats{$_} ";
}
close $tmpfh;

my $secs = $now - $last_timestamp;

my @mismatch;
my %stats_diff;

if($statefile_found and not $stats_missing){
    if($secs < 0){
        quit "UNKNOWN", "Last timestamp was in the future! Resetting...";
    } elsif ($secs == 0){
        quit "UNKNOWN", "0 seconds since last run, aborting...";
    }

    # Only do per sec for things that make sense, 1 collision or 1 error will average out to 0 after 1 sec
    foreach(qw/RX_packets RX_bytes TX_packets TX_bytes/){
        $stats_diff{$_} = int((($stats{$_} - $last_stats{$_} ) / $secs) + 0.5);
        if ($stats_diff{$_} < 0) {
            quit "UNKNOWN", "recorded stat $_ is higher than current stat, resetting stats";
        }
    }

    if($verbose >= 2){
        print "epoch now:                           $now\n";
        print "last run epoch:                      $last_timestamp\n";
        print "secs since last check:               $secs\n\n";
        printf "%-20s %-20s %-20s %-20s\n", "Stat", "Current", "Last", "Diff/sec";
        foreach(sort keys %stats_diff){
            printf "%-20s %-20s %-20s %-20s\n", $_, $stats{$_}, $last_stats{$_}, $stats_diff{$_};
        }
        print "\n\n";
    }

    if(defined($expected_mtu)){
        if($expected_mtu ne $mtu){
            push(@mismatch, "MTU");
        }
    }
}

my ($speed, $duplex, $link);

set_sudo("root");
$cmd = "$sudo $ethtool $interface 2>&1";

my @output = cmd($cmd);
foreach(@output){
    chomp;
    vlog3 "$_";
    if(/^\s*Speed:\s+(\d+)Mb\/s\s*$/){
        $speed = $1;
    } elsif(/^\s*Duplex:\s+(\w+)\s*$/){
        $duplex = $1;
    } elsif(/^\s*Link\s+detected:\s+(\w+)\s*$/){
        $link = $1;
    }
}
close $fh;
vlog2 "\n";

# Speed / Duplex / Link Detected

if(defined($link)){
    unless ($link eq "yes"){
        quit "CRITICAL", "Link detected: $link ";
    }
} else {
    quit "UNKNOWN", "Link status not found in '$ethtool' output! ";
}

if(defined($duplex)){
    if(defined($expected_duplex)){
        if($duplex ne $expected_duplex){
            push(@mismatch, "Duplex");
        }
    }
} else {
    quit "UNKNOWN", "Duplex not found in '$ethtool' output!" unless $bond;
}

if(defined($speed)){
    if(defined($expected_speed)){
        if($speed ne $expected_speed){
            push(@mismatch, "Speed");
        }
    }
} else {
    quit "UNKNOWN", "Speed not found in '$ethtool' output!" unless $bond;
}

my %interface_errors;
if($errors and $statefile_found and not $stats_missing){
    foreach(sort keys %stats){
        next if /bytes|packets/;
        next if ($_ eq "interrupts" and $stats{$_} eq "N/A");
        if($stats{$_} > $last_stats{$_}){
            $interface_errors{$_} = $stats{$_} - $last_stats{$_};
        }
    }
    if(scalar keys %interface_errors > 0){
        critical;
        foreach(sort keys %interface_errors){
            $msg .= "$interface_errors{$_} ";
            if($interface_errors{$_} < 2){
                $_ =~ s/s$//;
            }
            $msg .= "$_/";
        }
        $msg =~ s/\/$/! /;
    }
}

critical if @mismatch;
if(scalar @mismatch eq 1){
    $msg .= "$mismatch[0] mismatch! ";
} elsif(scalar @mismatch > 1){
    foreach(sort @mismatch){
        $msg .= "$_/";
    }
    $msg =~ s/\/$//;
    $msg .= " mismatch! ";
}

if (defined($expected_promisc) and $promisc ne $expected_promisc){
    $msg .= "PROMISC Mode $promisc! ";
    $msg .= "(expected $expected_promisc) " unless $short;
    critical;
}
unless($bond){
    $msg .= "Speed:${speed}Mb/s ";
    $msg .= "(expected:${expected_speed}Mb/s) " if (not $short and defined($expected_speed) and $speed ne $expected_speed);
    $msg .= "Duplex:$duplex ";
    $msg .= "(expected:${expected_duplex}) " if (not $short and defined($expected_duplex) and $duplex ne $expected_duplex);
}
$msg .= "MTU:$mtu ";
$msg .= "(expected:$expected_mtu) " if (not $short and defined($expected_mtu) and $expected_mtu ne $mtu);
$msg .= "Mac:$mac";
if(!(defined($expected_promisc) and $promisc ne $expected_promisc)){
    $msg .= " Promisc:$promisc";
}
if(not $statefile_found) {
    $msg .= " (state file not found, first run of plugin? - stats will be available from next run)";
} elsif ($stats_missing){
    $msg .= " (stats missing from state file, resetting values, should be available from next run)";
} else {
    $msg .= "|";
    foreach(sort keys %stats){
        next if ($_ eq "interrupts" and $stats{$_} eq "N/A");
        if(defined($stats_diff{$_})){
            $msg .= "'$_/sec'=$stats_diff{$_} ";
        } else {
            $msg .= "$_=$stats{$_} ";
        }
    }
}

quit $status, $msg;
