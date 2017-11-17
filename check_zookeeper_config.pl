#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-02-09 15:44:43 +0000 (Sat, 09 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a ZooKeeper server's running config against a given configuration file

Useful for checking

1. Configuration Compliance against a baseline
2. Puppet has correctly deployed revision controlled config version

Inspired by check_mysql_config.pl (also part of the Advanced Nagios Plugins Collection)

Requires ZooKeeper 3.3.0 onwards.

Tested on Apache ZooKeeper 3.3.6, 3.4.5, 3.4.6, 3.4.8, 3.4.11 and on Cloudera, Hortonworks and MapR.

BUGS: there are bugs in ZooKeeper's live running config where it doesn't report all the configuration variables from the config file. I checked this with my colleague Patrick Hunt @ Cloudera who reviewed those additions. If you get a warning about missing config not found on running server then you can use the -m switch to ignore it but please also raise a ticket to create an exception for that variable at https://github.com/harisekhon/nagios-plugins/issues/new
";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
    use lib dirname(__FILE__) . "/nagios-lib";
}
use HariSekhonUtils;
use HariSekhon::ZooKeeper;

# Turns out these not being present is a bug
# Try to find time to patch this in ZooKeeper later
my @config_file_only = qw(
                             autopurge.purgeInterval
                             autopurge.snapRetainCount
                             initLimit
                             leaderServes
                             syncLimit
                             server\.\d+
                       );

# defaults appear when nothing in config file
my @running_only = qw(
                            dataLogDir
                            maxClientCnxns
                            maxSessionTimeout
                            minSessionTimeout
);

$host = "localhost";

my $ZK_DEFAULT_CONFIG = "/etc/zookeeper/conf/zoo.cfg";
my $conf              = $ZK_DEFAULT_CONFIG;
my $no_warn_extra     = 0;
my $no_warn_missing   = 0;

%options = (
    "H|host=s"          => [ \$host,             "Host to connect to (defaults: localhost, \$ZOOKEEPER_HOST, \$HOST)" ],
    "P|port=s"          => [ \$port,             "Port to connect to (defaults: $ZK_DEFAULT_PORT, set to 5181 for MapR, \$ZOOKEEPER_PORT, \$PORT)" ],
    "C|config=s"        => [ \$conf,             "ZooKeeper config file (defaults to $ZK_DEFAULT_CONFIG)" ],
    "e|no-warn-extra"   => [ \$no_warn_extra,    "Don't warn on extra config detected on ZooKeeper server that isn't specified in config file (serverId is omitted either way)" ],
    "m|no-warn-missing" => [ \$no_warn_missing,  "Don't warn on missing config detected on ZooKeeper server that was expected from config file (see Bug note in --help description header)" ],
);

@usage_order = qw/host port config no-warn-extra/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$conf       = validate_file($conf, "zookeeper config");

vlog2;
set_timeout();

vlog2 "reading zookeeper config file";
my $fh = open_file $conf;
vlog3;
vlog3 "=====================";
vlog3 "ZooKeeper config file";
vlog3 "=====================";
my %config;
while(<$fh>){
    chomp;
    s/#.*//;
    next if /^\s*$/;
    s/^\s*//;
    s/\s*$//;
    vlog3 "config:  $_";
    /^\s*[\w\.]+\s*=\s*.+$/ or quit "UNKNOWN", "unrecognized line in config file '$conf': '$_'. $nagios_plugins_support_msg";
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    if($key eq "dataDir" or $key eq "dataLogDir"){
        $value =~ s/\/$//;
        $value .= "/version-2";
    }
    $config{$key} = $value;
}
vlog3;

$status = "OK";

vlog2;
vlog2 "getting running zookeeper config from '$host:$port'";
vlog3;
zoo_cmd "conf", $timeout - 1;
vlog3;
vlog3 "========================";
vlog3 "ZooKeeper running config";
vlog3 "========================";
my %running_config;
while(<$zk_conn>){
    chomp;
    s/#.*//;
    next if /^\s*$/;
    s/^\s*//;
    s/\s*$//;
    vlog3 "running config: $_";
    my ($key, $value) = split(/\s*=\s*/, $_, 2);
    next if $key =~ /^serverId$/;
    $running_config{$key} = $value;
}
vlog2;

my @missing_config;
my @mismatched_config;
my @extra_config;
foreach my $key (sort keys %config){
    unless(defined($running_config{$key})){
        if(grep { $key =~ /^$_$/ } @config_file_only){
            vlog2 "config only, but exempted due to ZK bug: $key";
            next;
        } else {
            push(@missing_config, $key);
        }
        next;
    }
    unless($config{$key} eq $running_config{$key}){
        push(@mismatched_config, $key);
    }
}
vlog2;

foreach my $key (sort keys %running_config){
    unless(defined($config{$key})){
        if(grep { $_ eq $key } @running_only){
            vlog2 "running only, but exempted: $key";
            next;
        }
        push(@extra_config, $key);
    }
}

$msg = "";
if(@mismatched_config){
    critical;
    #$msg .= "mismatched config: ";
    foreach(sort @mismatched_config){
        $msg .= "$_ value mismatch '$config{$_}' in config vs '$running_config{$_}' live on server, ";
    }
}
if((!$no_warn_missing) and @missing_config){
    warning;
    $msg .= "config missing on running server: ";
    foreach(sort @missing_config){
        $msg .= "$_, ";
    }
    $msg =~ s/, $//;
    $msg .= ", ";
}
if((!$no_warn_extra) and @extra_config){
    warning;
    $msg .= "extra config found on running server: ";
    foreach(sort @extra_config){
        $msg .= "$_=$running_config{$_}, ";
    }
    $msg =~ s/, $//;
    $msg .= ", ";
}

$msg = sprintf("%d config values tested from config file '$conf', %s", scalar keys %config, $msg);
$msg =~ s/, $//;

vlog2;
quit $status, $msg;
