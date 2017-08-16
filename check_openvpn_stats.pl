#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-06-13 10:52:43 +0100 (Wed, 13 Jun 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to show OpenVPN stats by parsing the status log";

$VERSION = "0.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;

my $DEFAULT_MAX_AGE = 60;

my $max_age = $DEFAULT_MAX_AGE;
my $status_log;
my %openvpn_users;
my $user_regex = '\\w+';
my $date_regex = '\w{3} \w{3} {1,2}\d{1,2} \d{1,2}:\d{2}:\d{2} \d{4}';
my %stats;

# regex to skip
my @skip_regex = (
    "OpenVPN CLIENT LIST",
    "Updated,$date_regex",
    "Common Name,Real Address,Bytes Received,Bytes Sent,Connected Since",
    "$user_regex,$ip_regex:\\d+,\\d+,\\d+,$date_regex",
    "ROUTING TABLE",
    "Virtual Address,Common Name,Real Address,Last Ref",
    "GLOBAL STATS",
    "END",
);
my $skip_regex = join("|", @skip_regex);
$skip_regex = qr/^$skip_regex$/io;

%options = (
    "s|status-log=s" => [ \$status_log, "OpenVPN status log file to read" ],
    "a|max-age=i"    => [ \$max_age,    "Max age in secs of log (defaults to $DEFAULT_MAX_AGE)" ],
);
@usage_order = qw/status-log max-age/;

get_options();

$status_log = validate_filename($status_log);

vlog2;
set_timeout();

$status = "OK";

my $fh       = open_file $status_log;
my $file_age = time - (stat($status_log))[9];
vlog2 "file age: $file_age secs";
if($file_age > $max_age){
    quit "CRITICAL", "OpenVPN status log is $file_age secs old (> $max_age)";
}

debug "skipping lines matching regex: $skip_regex";
while(<$fh>){
    chomp;
    if(/^($ip_regex),($user_regex),($ip_regex)(:?:\d+)?,$date_regex$/){
        @{$openvpn_users{$2}} = ($3 , $1);
    } elsif(/^Max bcast\/mcast queue length,(\d+)$/){
        $stats{"queue"} = $1;
    } elsif(/$skip_regex/){
        # pass
    } else {
        quit "UNKNOWN", "unrecognized line found in openvpn status log: '$_'";
    }
}

foreach(sort keys %openvpn_users){
    $msg .= "$_ ($openvpn_users{$_}[0]=>$openvpn_users{$_}[1]), "
}
$msg =~ s/, $//;
my $user_count = scalar keys %openvpn_users;
plural($user_count);
$msg = sprintf("%d user$plural - $msg", $user_count);
$msg .= " | openvpn_users=$user_count";
$msg .= " 'bcast/mcast queue'=$stats{queue}" if defined($stats{"queue"});

quit $status, $msg;
