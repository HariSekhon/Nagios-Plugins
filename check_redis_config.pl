#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-11-17 21:08:10 +0000 (Sun, 17 Nov 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Redis server's running config against a given configuration file

Useful for checking

1. Configuration Compliance against a baseline
2. Puppet has correctly deployed revision controlled config version

Detects password in this order of priority (highest first):

1. --password command line switch
2. \$REDIS_PASSWORD environment variable (recommended)
3. requirepass setting in config file

Inspired by check_mysql_config.pl (also part of the Advanced Nagios Plugins Collection)

Tested on Redis 2.4, 2.6, 2.8, 3.0, 3.2, 4.0";

$VERSION = "0.8.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :regex/;
use HariSekhon::Redis;
#use Cwd 'abs_path';
use IO::Socket;

my $default_config_cmd = "config";
my $config_cmd = $default_config_cmd;

# REGEX
my @config_file_only = qw(
                           activerehashing
                           appendfilename
                           bind
                           daemonize
                           databases
                           include
                           logfile
                           maxclients
                           pidfile
                           port
                           rdbcompression
                           rename-command
                           slaveof
                           syslog-.*
                           vm-.*
                       );

my @running_conf_only = qw(
                            maxmemory.*
                       );

my @default_config_locations = qw(
    /etc/redis/redis.conf
    /etc/redis.conf
);
my $conf;

my $no_warn_extra     = 0;
my $no_warn_missing   = 0;

our %options = (
    %redis_options,
    "C|config=s"        =>  [ \$conf,               "Redis config file (defaults: @default_config_locations)" ],
    "no-warn-missing"   =>  [ \$no_warn_missing,    "Do not warn on missing config variables found in config file but not on live server" ],
    "no-warn-extra"     =>  [ \$no_warn_extra,      "Do not warn on extra config variables found on server but not in config file" ],
);
delete $options{"precision=i"};

@usage_order = qw/host port password config no-warn-missing no-warn-extra/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$password   = validate_password($password) if $password;
unless($conf){
    vlog2 "no config specified";
    foreach(@default_config_locations){
        if( -f $_ ){
            unless( -r $_ ) {
                warn "config '$_' found but not readable!\n";
                next;
            }
            $conf = $_;
            vlog2 "found config: $_";
            last;
        }
    }
}
$conf = validate_file($conf, "config");
vlog_option_bool "warn on missing", ! $no_warn_missing;
vlog_option_bool "warn on extra", ! $no_warn_extra;


vlog2;
set_timeout();

vlog2 "reading redis config file";
my $fh = open_file $conf;
vlog3;
vlog3 "=====================";
vlog3 "  Redis config file";
vlog3 "=====================";
my %config;
my ($key, $value);
while(<$fh>){
    chomp;
    s/#.*//;
    next if /^\s*$/;
    s/^\s*//;
    s/\s*$//;
    debug "conf file:  $_";
    /^\s*([\w\.-]+)(?:\s+["']?([^'"]*)["']?)?\s*$/ or quit "UNKNOWN", "unrecognized line in config file '$conf': '$_'. $nagios_plugins_support_msg";
    $key   = lc $1;
    if(defined($2)){
        $value = lc $2;
    } else {
        $value = "";
    }
    if($key eq "dir"){
        # this checks the file system and returns undef when /var/lib/redis isn't found when checking from my remote Mac
        #$value = abs_path($value);
        # Redis live running server displays the dir without trailing slash unlike default config
        $value =~ s/\/+$//;
    } elsif ($key eq "requirepass"){
        unless($password){
            if($value and $value ne "<omitted>"){
                vlog2 "detected and using password from config file";
                $password = $value;
            }
        }
        $value = "<omitted>";
    } elsif ($key eq "rename-command"){
        my @tmp = split(/\s+/, $value);
        # if rename-command config " " this block is never entered
        if(scalar @tmp == 2){
            if($tmp[0] eq "config"){
                $config_cmd = $tmp[1];
                $config_cmd =~ s/["'`]//g;
                quit "UNKNOWN", "config command was disabled in config file '$conf' using rename-command" unless $config_cmd;
            }
        }
    }
    if($value =~ /^(\d+(?:\.\d+)?)([KMGTP]B)$/i){
        $value = expand_units($1, $2);
    }
    vlog3 "config:  $key = $value";
    if($key eq "save"){
        if(defined($config{$key})){
            $value = "$config{$key} $value";
        }
    }
    $config{$key} = $value;
}
vlog3 "=====================";

if($config_cmd ne $default_config_cmd){
    vlog2 "\nfound alternative config command '$config_cmd' from config file '$conf'";
}
$config_cmd =~ /^([\w-]+)$/ || quit "UNKNOWN", "config command was set to a non alphanumeric string '$config_cmd', aborting, check config file '$conf' for 'rename-command CONFIG'";
$config_cmd = $1;
vlog2;

$status = "OK";

# API libraries don't support config command, using direct socket connect, will do protocol myself
#my $redis = connect_redis(host => $host, port => $port, password => $password) || quit "CRITICAL", "failed to connect to redis server '$hostport'";

vlog2 "getting running redis config from '$host:$port'";

my $ip = validate_resolvable($host);
vlog2 "resolved $host to $ip";

$/ = "\r\n";
vlog2 "connecting to redis server $ip:$port ($host)";
my $redis_conn = IO::Socket::INET->new (
                                    Proto    => "tcp",
                                    PeerAddr => $ip,
                                    PeerPort => $port,
                                    Timeout  => $timeout,
                                 ) or quit "CRITICAL", sprintf("Failed to connect to '%s:%s'%s: $!", $ip, $port, (defined($timeout) and ($debug or $verbose > 2)) ? " within $timeout secs" : "");

vlog2;
if($password){
    vlog2 "sending redis password";
    print $redis_conn "auth $password\r\n";
    my $output = <$redis_conn>;
    chomp $output;
    unless($output =~ /^\+OK$/){
        quit "CRITICAL", "auth failed, returned: $output";
    }
    vlog2;
}

vlog2 "sending redis command: $config_cmd get *\n";
print $redis_conn "$config_cmd get *\r\n";
my $num_args = <$redis_conn>;
if($num_args =~ /^-|ERR/){
    chomp $num_args;
    $num_args =~ s/^-//;
    if($num_args =~ /operation not permitted/){
        quit "CRITICAL", "$num_args (authentication required? try --password)";
    } elsif ($num_args =~ /unknown command/){
        quit "CRITICAL", "$num_args (command disabled or renamed via 'rename-command' in config file '$conf'?)";
    } else {
        quit "CRITICAL", "error: $num_args";
    }
}
$num_args =~ /^\*(\d+)\r$/ or quit "CRITICAL", "unexpected response: $num_args";
$num_args = $1;
vlog2 sprintf("%s config settings offered by server\n", $num_args / 2);
my ($key_bytes, $value_bytes);
my %running_config;
vlog3 "========================";
vlog3 "  Redis running config";
vlog3 "========================";
my $null_configs_counter = 0;
foreach(my $i=0; $i < ($num_args / 2); $i++){
    $key_bytes  = <$redis_conn>;
    chomp $key_bytes;
    debug "key bytes:  $key_bytes";
    $key_bytes =~ /^\$(\d+)$/ or quit "UNKNOWN", "protocol error, invalid key bytes line received: $key_bytes";
    $key_bytes = $1;
    $key        = <$redis_conn>;
    chomp $key;
    debug "key:        $key";
    $key   = lc $key;
    ($key_bytes eq length($key)) or quit "UNKNOWN", "protocol error, num bytes does not match length of argument for $key ($key_bytes bytes expected, got " . length($key) . ")";
    $value_bytes = <$redis_conn>;
    chomp $value_bytes;
    debug "data bytes: $value_bytes";
    $value_bytes =~ /^\$(-?\d+)$/ or quit "UNKNOWN", "protocol error, invalid data bytes line received: $value_bytes";
    $value_bytes = $1;
    if($value_bytes == -1){
        $null_configs_counter++;
        next;
    }
    $value       = <$redis_conn>;
    chomp $value;
    $value = lc $value;
    ($value_bytes eq length($value)) or quit "UNKNOWN", "protocol error, num bytes does not match length of argument for $value ($value_bytes bytes expected, got " . length($value) . ")";
    if($key eq "requirepass"){
        $value = "<omitted>";
    }
    debug "data:       $value";
    vlog3 "running config:  $key=$value";
    if(defined($running_config{$key})){
        quit "UNKNOWN", "duplicate running config key detected. $nagios_plugins_support_msg";
    }
    $running_config{$key} = $value;
}
vlog3 "========================";
plural $null_configs_counter;
vlog2 sprintf("%s config settings parsed from server, %s null config$plural skipped\n", scalar keys %running_config, $null_configs_counter);
vlog3 "========================";

unless(($num_args/2) == ((scalar keys %running_config) + $null_configs_counter)){
    quit "UNKNOWN", "mismatch on number of config settings expected and parsed";
}

my @missing_config;
my @mismatched_config;
my @extra_config;
foreach my $key (sort keys %config){
    unless(defined($running_config{$key})){
        if(grep { $key =~ /^$_$/ } @config_file_only){
            vlog3 "skipping: $key (config file only)";
            next;
        } else {
            push(@missing_config, $key);
        }
        next;
    }
    my $running_value = $running_config{$key};
    my $config_value  = $config{$key};
    # special exception of client-output-buffer-limit in Travis, couldn't make generic as it also requires special prefix handling
    if($key eq "client-output-buffer-limit"){
        my $tmp = "";
        foreach my $tmp2 (split(/\s/, $config_value)){
            foreach my $unit (qw/kb mb gb tb pb/){
                if($tmp2 =~ /^(\d+)($unit)$/i){
                    $tmp2 = expand_units($1, $2, "client-output-buffer-limit");
                    last;
                }
            }
            $tmp .= " $tmp2";
        }
        $config_value = trim($tmp);
        my $regex_prefix = 'normal\s+\d+\s+\d+\s+\d+\s+slave\s+\d+\s+\d+\s+\d+\s+';
        if($config{$key} ne $config_value){
            vlog2 "translated $key value '$config{$key}' => '$config_value' for comparison and prefixing '$regex_prefix'";
        }
        unless($running_value =~ /^($regex_prefix)?\Q$config_value\E$/){
            push(@mismatched_config, $key);
        }
    } else {
        unless($running_value eq $config_value){
            push(@mismatched_config, $key);
        }
    }
}

foreach my $key (sort keys %running_config){
    unless(defined($config{$key})){
        if(grep { $key =~ /^$_$/ } @running_conf_only){
            vlog3 "skipping: $key (running config only)";
        } else {
            push(@extra_config, $key);
        }
    }
}
vlog3;

$msg = "";
if(@mismatched_config){
    critical;
    $msg .= "mismatched config in file vs live running server: ";
    foreach(sort @mismatched_config){
        $msg .= "$_ = '$config{$_}' vs '$running_config{$_}', ";
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
if(@extra_config){
    warning unless $no_warn_extra;
    if($verbose or not $no_warn_extra){
        $msg .= "extra config found on running server: ";
        foreach(sort @extra_config){
            $msg .= "$_=$running_config{$_}, ";
        }
        $msg =~ s/, $//;
        $msg .= ", ";
    }
}

$msg = sprintf("%d config values tested from config file '%s', %s", scalar keys %config, $conf, $msg);
$msg =~ s/, $//;

quit $status, $msg;
