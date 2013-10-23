#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-06-02 11:26:16 +0100 (Thu, 02 Jun 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check MySQL config file matches running MySQL server configuration

Primarily written to check that DBAs hadn't changed any running DB from Puppet deployed config without backporting their changes

A friend and ex-colleague of mine Tom Liakos @ Specificmedia pointed out a long time after I wrote this that Percona independently developed a similar tool called pt-config-diff (part of the Percona toolkit) around the same time.";

$VERSION = "0.9.21";

use strict;
use warnings;
use DBI;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

my $default_config_file     = "/etc/my.cnf";
my $default_host            = "127.0.0.1";
my $default_port            = "3306";
my $default_user            = "root";
my $default_mysql_instance  = "mysqld";
my $default_mysql_socket    = "/var/lib/mysql/mysql.sock";

my $config_file     = $default_config_file;
   $host            = $default_host;
   $port            = $default_port;
my $mysql_instance  = $default_mysql_instance;
my $mysql_socket    = $default_mysql_socket;
my $password        = "";
my $user            = $default_user;
my %mysql_config;
my $ensure_skip_name_resolve = 0;
my $warn_on_missing_variables = 0;

# using regex here now
my @config_file_only = (
    "binlog-(?:do|ignore)-db",
    "default-storage-engine",
    "federated",
    "log-bin-index",
    "log-slow-slave-statements",
    "master-(?:host|port|user|password|info-file)",
    "master-info-file",
    "plugin-load",
    "relay-log",
    "relay-log-index",
    "relay_log_info_file",
    "replicate-ignore(?:db|table)",
    "skip-bdb",
    "user",
    #"log-bin.*",
    #"myisam-recover",
    #"relay-log.*",
    #"server-id",
    #"skip-slave-start",
);

my @mysql_on_off = (
    "log-bin",
    "log-slow-queries",
    "skip-slave-start",
);

my %mysql_convert_names = (
    "myisam-recover"    => "myisam_recover_options",
    "skip-slave-start"  => "init_slave",
);

# Mode translations taken from MySQL documentation http://dev.mysql.com/doc/refman/5.0/en/server-sql-mode.html
my %mysql_modes = (
    "ANSI"          => "REAL_AS_FLOAT, PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE",
    "DB2"           => "PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS",
    "MAXDB"         => "PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS, NO_AUTO_CREATE_USER",
    "MSSQL"         => "PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS",
    "MYSQL323"      => "NO_FIELD_OPTIONS, HIGH_NOT_PRECEDENCE",
    "MYSQL40"       => "NO_FIELD_OPTIONS, HIGH_NOT_PRECEDENCE",
    "ORACLE"        => "PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS, NO_AUTO_CREATE_USER",
    "POSTGRESQL"    => "PIPES_AS_CONCAT, ANSI_QUOTES, IGNORE_SPACE, NO_KEY_OPTIONS, NO_TABLE_OPTIONS, NO_FIELD_OPTIONS",
    "TRADITIONAL"   => "STRICT_TRANS_TABLES, STRICT_ALL_TABLES, NO_ZERO_IN_DATE, NO_ZERO_DATE, ERROR_FOR_DIVISION_BY_ZERO, NO_AUTO_CREATE_USER"
);

%options = (
    "H|host=s"                  => [ \$host,            "MySQL host to check (default: $default_host). Set to blank to connect via socket" ],
    "P|port=i"                  => [ \$port,            "MySQL port to connect to (default: $default_port)" ],
    "c|config|config-file=s"    => [ \$config_file,     "Path to MySQL my.cnf config file (default: $default_config_file)" ],
    "u|mysql-user=s"            => [ \$user,            "MySQL username to use to connect to local MySQL connection (default: $default_user)" ],
    "p|mysql-password=s"        => [ \$password,        "MySQL Password to use to connect to local MySQL connection (default: empty)" ],
    "d|mysql-instance=s"        => [ \$mysql_instance,  "MySQL [instance] in my.cnf to test (default: $default_mysql_instance)" ],
    "s|mysql-socket=s"          => [ \$mysql_socket,    "MySQL socket file through which to connect (default: $default_mysql_socket)" ],
    "skip-name-resolve"         => [ \$ensure_skip_name_resolve, "Ensure that skip-name-resolve is specified in the config file" ],
    "warn-on-missing"           => [ \$warn_on_missing_variables, "Return warning when there my.cnf variables missing from running MySQL config. Default is just to list them but return OK unless there is an actual mismatch. Useful if you want to make sure they're all accounted for as sometimes they only appear in config file or the live name is different to the config file name" ],
);
@usage_order = qw/config-file host port mysql-user mysql-password mysql-instance skip-name-resolve warn-on-missing/;

get_options();

$host        = validate_host($host) if $host;
$port        = validate_port($port);
$user        = validate_user($user);
$password    = validate_password($password) if $password;
$config_file = validate_filename($config_file);
vlog2 "config file: '$config_file'";
$mysql_instance = validate_database($mysql_instance);
$mysql_socket = validate_filename($mysql_socket, 1) or usage "Invalid MySQL Socket given, did not pass file regex: $mysql_socket";

vlog2;
set_timeout();

my $fh = open_file $config_file;
sub parse_my_cnf {
    my $fh = shift;
    while(<$fh>){
        chomp;
        vlog3 "$_";
        next unless /^\s*\[$mysql_instance\]\s*$/;
        vlog2 "found $mysql_instance section";
        last;
    }
    my $name;
    my $val;
    while(<$fh>){
        last if /^\s*\[.+\]\s*$/;
        s/#.*$//;
        next if /^\s*$/;
        # TODO: add plugin validation code
        next if /^\s*plugin-load\s*=\s*innodb=ha_innodb_plugin\.so\s*;\s*innodb_trx=ha_innodb_plugin\.so\s*;\s*innodb_locks=ha_innodb_plugin\.so\s*;\s*innodb_lock_waits=ha_innodb_plugin\.so\s*;\s*innodb_cmp=ha_innodb_plugin\.so\s*;\s*innodb_cmp_reset=ha_innodb_plugin\.so\s*;\s*innodb_cmpmem=ha_innodb_plugin\.so\s*;\s*innodb_cmpmem_reset=ha_innodb_plugin\.so\s*$/;
        chomp;
        /^\s*([\w-]+)\s*(?:=\s*([\/\w\:\,\.=-]+)\s*)?$/ or quit "CRITICAL", "unrecognized line in config file '$config_file': '$_' (not in expected format)";

        $name = $1;
        $val  = $2;
        if($name eq "defaults-extra-file"){
            unless($val){
                vlog2 "defaults-extra-file found but blank, skipping";
                next;
            }
            vlog2 "found defaults-extra-file '$val', opening..";
            $fh = open_file $val;
            # This is reset to mysqld in the defaults-extra-file on master-mdb302-dc3
            $mysql_instance = "mysqld";
            parse_my_cnf($fh);
            next;
        }
        if(defined $val){
            $mysql_config{$name} = "$val";
            if($val =~ /^(\d+)K$/io){
                vlog2 "converting $name from KB to bytes";
                $mysql_config{$name} = $1 * 1024;
            } elsif($val =~ /^(\d+)M$/io){
                vlog2 "converting $name from MB to bytes";
                $mysql_config{$name} = $1 * 1024 * 1024;
            } elsif ($val =~ /^(\d+)G$/io){
                vlog2 "converting $name from GB to bytes";
                $mysql_config{$name} = $1 * 1024 * 1024 * 1024;
            }
        } else {
            $mysql_config{$name} = "ON";
        }
    }
}
parse_my_cnf($fh);

if(scalar keys %mysql_config < 1){
    quit "CRITICAL", "No MySQL config variables found in config file '$config_file' for instance ['$mysql_instance']. Is this a valid MySQL config file or do you need to specify a different instance name?";
}

vlog3;
vlog3 "===========================";
vlog3 "MySQL Config File Variables";
vlog3 "===========================";
foreach(sort keys %mysql_config){
    vlog3 "$_ = $mysql_config{$_}";
}

###################
# Connect to MySQL

vlog2 "\nconnecting to MySQL database on '$host:$port' as '$user'\n";
my $dbh;
if($host){
    $dbh = DBI->connect("DBI:mysql:;host=$host;port=$port", $user, $password, { PrintError => 0 }) || quit "CRITICAL", "failed to connect to MySQL database on '$host:$port': $DBI::errstr";
} else { # connect through local socket
    $dbh = DBI->connect("DBI:mysql:", $user, $password, { mysql_socket => $mysql_socket, PrintError => 0 }) || quit "CRITICAL", "failed to connect to MySQL database through socket: $DBI::errstr";
}

my $sql = "show global variables";
my $sth = $dbh->prepare($sql);
vlog2 "executing query: $sql";
$sth->execute or quit "CRITICAL", "SQL Error - $DBI::errstr";
my %mysql_variables;
vlog3;
vlog3 "======================";
vlog3 "MySQL Global Variables";
vlog3 "======================";
my $ref;
while($ref = $sth->fetchrow_arrayref){
    vlog3 "$$ref[0] = $$ref[1]";
    $mysql_variables{$$ref[0]} = $$ref[1];
}
$sth->finish();
vlog2 "closed MySQL statement\n";
$sql = "show status like 'uptime'";
$sth = $dbh->prepare($sql);
vlog2 "executing query: $sql";
$sth->execute or quit "CRITICAL", "SQL Error - $DBI::errstr";
$ref = $sth->fetchrow_arrayref;
vlog3 "Result: $$ref[0] = $$ref[1]";
unless($$ref[0] eq "Uptime"){
    quit "UNKNOWN", "Failed to get uptime from MySQL Server, got '$$ref[0]' instead of 'Uptime'";
}
my $mysql_uptime = $$ref[1];
$mysql_uptime =~ /^-?\d+$/ or quit "UNKNOWN", "Failed to get uptime from MySQL Server, got '$mysql_uptime' instead of seconds";
vlog2 "mysql server uptime is '$mysql_uptime' seconds";
vlog2 "closed MySQL statement\n";
$sth->finish();
$dbh->disconnect();
vlog2 "disconnected from MySQL database\n";

my $mtime = (stat $fh)[9] or quit "UNKNOWN", "Failed to stat config file '$config_file': $!";
$mtime =~ /^-?\d+$/ or quit "UNKNOWN", "Failed to get mtime of config file '$config_file', got '$mtime' instead of seconds";
my $last_edited = time - $mtime;
vlog2 "config file '$config_file' was changed '$last_edited' seconds ago\n";

# Could check for time consistency here but it really doesn't matter, it doesn't validate/invalidate anything, this is purely informational

sub humantime {
    my $secs = $_[0];
    my $mins  = 0;
    my $hours = 0;
    my $days  = 0;
    if($secs > 60){
        $mins = int($secs / 60);
        $secs = $secs - (int($secs / 60)*60);
    }
    if($mins > 60){
        $hours = int($mins / 60);
        $mins  = $mins - (int($mins / 60)*60);
    }
    if($hours > 24){
        $days  = int($hours / 24);
        $hours = $hours - (int($hours / 24)*24);
    }
    ($days, $hours, $mins, $secs);
}

my @last_edited  = humantime($last_edited);
my @mysql_uptime = humantime($mysql_uptime);

my $last_edited_msg  = "";
my $mysql_uptime_msg = "";

if($last_edited[0]){ $last_edited_msg .= "$last_edited[0] days "; }
if($last_edited[0] or $last_edited[1]){ $last_edited_msg .= "$last_edited[1] hours "; }
if($last_edited[0] or $last_edited[1] or $last_edited[2]){ $last_edited_msg .= "$last_edited[2] mins "; }
$last_edited_msg .= "$last_edited[3] secs";

if($mysql_uptime[0]){ $mysql_uptime_msg .= "$mysql_uptime[0] days "; }
if($mysql_uptime[0] or $mysql_uptime[1]){ $mysql_uptime_msg .= "$mysql_uptime[1] hours "; }
if($mysql_uptime[0] or $mysql_uptime[1] or $mysql_uptime[2]){ $mysql_uptime_msg .= "$mysql_uptime[2] mins "; }
$mysql_uptime_msg .= "$mysql_uptime[3] secs";

my $uptime_msg = "MySQL Server uptime: $mysql_uptime_msg, Config file last updated: $last_edited_msg ago";

$status = "OK";
$msg    = "";
my $variables_found = 0;
my @variables_not_found;
my $mysql_variable_name;
my $mysql_config;
my $mysql_variable;
#$mysql_config{"hari"} = "blah";
my $mysql_online_variable_name;
vlog2 "validating mysqld options in config file against what is live on server";

$mysql_variables{"version"} =~ /^\s*(\d+\.\d+\.\d+)(?:-.+)?\s*$/ or quit "UNKNOWN", "MySQL version did not match expected format, review and extend code as necessary";
my $mysql_version = $1;
vlog2 "detected MySQL version as $mysql_version";

####################################
# MySQL Version specific adjustments

sub version_lt {
    $_[0] =~ /^\d+(\.\d+)+$/ or code_error "non-numeric argument passed to version_lt() sub";
    my @tested_version = split(/\./, $_[0]);
    my @mysql_version  = split(/\./, $mysql_version);
    foreach(my $i=0;$i<scalar @tested_version;$i++){
        if($mysql_version[$i] < $tested_version[$i]){
            vlog2 "MySQL version < $_[0], specific adjustments being made:";
            return 1;
        }
    }
    return 0;
}

sub version_ge {
    $_[0] =~ /^\d+(\.\d+)+$/ or code_error "non-numeric argument passed to version_ge() sub";
    my @tested_version = split(/\./, $_[0]);
    my @mysql_version  = split(/\./, $mysql_version);
    foreach(my $i=0;$i<scalar @tested_version;$i++){
        if($mysql_version[$i] < $tested_version[$i]){
            return 0;
        } elsif($mysql_version[$i] > $tested_version[$i]){
            last;
        }
    }
    vlog2 "MySQL version >= $_[0], specific adjustments being made:";
    return 1;
}

if(version_lt "5.1"){
    vlog2 "=> disabling skip-name-resolve verification from global variables since it's not displayed prior to 5.1";
    push(@config_file_only, "skip-name-resolve");
}

if(version_ge "5.1.3"){
    vlog2 "=> mapping table_cache => table_open_cache";
    $mysql_convert_names{"table_cache"} = "table_open_cache";
}

if(version_ge "5.1.12"){
    if($mysql_config{"sql-mode"}){
        vlog2 "=> setting NO_ENGINE_SUBSTITUTION as on by default";
        $mysql_config{"sql-mode"} .= ",NO_ENGINE_SUBSTITUTION" if($mysql_config{"sql-mode"});
    }
}

####################################
# Now test those config variables

foreach $mysql_variable_name (sort keys %mysql_config){
    $mysql_online_variable_name = $mysql_variable_name;
    if(grep { $mysql_variable_name =~ /^$_$/ } (keys %mysql_convert_names)){
        vlog2 "mapping '$mysql_variable_name' to '$mysql_convert_names{$mysql_variable_name}'";
        $mysql_online_variable_name = $mysql_convert_names{$mysql_variable_name};
    }
    $mysql_online_variable_name =~ s/-/_/g;
    if(defined($mysql_variables{$mysql_online_variable_name})){
        $variables_found++;
        $mysql_config   = $mysql_config{$mysql_variable_name};
        $mysql_variable = $mysql_variables{$mysql_online_variable_name};
        if(grep { $mysql_variable_name =~ /^$_$/ } @mysql_on_off){
            vlog2 "changed comparison for '$mysql_variable_name' to ON/OFF rather than actual content";
            $mysql_config =~ s/^.+$/ON/;
            # added this for skip-slave-start which is mapped to init_slave which inverts the test
            $mysql_config =~ s/ON/OFF/ if ($mysql_variable_name =~ /^skip/);
        }
        # Normalize stuff as config file and global vars appear different
        $mysql_config   =~ s/^ALL$/1/;
        $mysql_variable =~ s/^ALL$/1/;
        $mysql_config   =~ s/^ON$/1/;
        $mysql_variable =~ s/^ON$/1/;
        $mysql_config   =~ s/^OFF$/0/;
        $mysql_variable =~ s/^OFF$/0/;
        # added this for init_slave which is blank instead of 0 or OFF
        $mysql_variable =~ s/^$/0/;
        $mysql_config   =~ s/\/$//;
        $mysql_variable =~ s/\/$//;
        $mysql_config   =~ s/^(\d+)\.0+$/$1/;
        $mysql_variable =~ s/^(\d+)\.0+$/$1/;
        if(lc $mysql_variable_name eq "sql-mode"){
            my $sql_mode_tmp = "";
            foreach(sort split(/\s*,\s*/, $mysql_config)){
                if($mysql_modes{$_}){
                    $sql_mode_tmp .= "$mysql_modes{$_},";
                }
                $sql_mode_tmp .= "$_,";
            }
            $sql_mode_tmp   =~ s/^\s*//;
            $sql_mode_tmp   =~ s/\s*,*\s*$//;
            $mysql_config   = $sql_mode_tmp;
            #sort keys %{{ map { $_ => 1 } split(/\s*,\s*/, $mysql_config) }}
            #$mysql_config   = join(",", sort split(/\s*,\s*/, $mysql_config)   );
            # This makes sure that each element is unique by assigning to keys in a hash, then fetching and sorting keys and joining
            $mysql_config   = join(",", sort keys %{{ map { $_ => 1 } split(/\s*,\s*/, $mysql_config) }} );
            $mysql_variable = join(",", sort split(/\s*,\s*/, $mysql_variable) );
            vlog2 "* Normalized MySQL Modes *\nConfig File SQL Modes: $mysql_config\nMySQL Server SQL Modes: $mysql_variable\n";
        }
        $mysql_config   = lc($mysql_config);
        $mysql_variable = lc($mysql_variable);
        if($mysql_variable ne $mysql_config){
            critical;
            $msg .= "$mysql_variable_name value mismatch '$mysql_config{$mysql_variable_name}' in config file '$config_file' vs '$mysql_variables{$mysql_online_variable_name}' live on server, ";
        }
    } else {
        my $not_found_msg = "'$mysql_variable_name' not found in MySQL server's global variables list, skipping";
        # Special handling for skip-name-resolve on Linux
        # This turned out to be too non-standard, and therefore it's better to just upgrade to 5.1 which has the variable
        #if($mysql_variable_name eq "skip-name-resolve"){
        #    if( $^O eq "linux" ){
        #        vlog2 "running on Linux, performing extra process check for skip-name-resolve";
        #        `ps -ef 2>&1 | grep -q "mysql[d] .*--skip-name-resolve"`;
        #        if($? eq 0){
        #            vlog2 "skip-name-resolve was found in processlist: OK:";
        #        } else {
        #            $status = "CRITICAL";
        #            $msg .= "$mysql_variable_name mismatch (enabled in config file '$config_file' but not found in process list), ";
        #        }
        #    } else {
        #        vlog2 "$not_found_msg (special exception - not running on Linux therefore not testing process list for this)";
        #    }
        #} elsif(grep { $mysql_variable_name =~ /^$_$/ } @config_file_only){
        if(grep { $mysql_variable_name =~ /^$_$/ } @config_file_only){
            vlog2 "$not_found_msg (exception)...";
        } else {
            vlog2 "$not_found_msg with note...";
            push(@variables_not_found, $mysql_variable_name);
        }
    }
}
vlog2 "";
$msg =~ s/, $/. /;
if($ensure_skip_name_resolve and not $mysql_config{"skip-name-resolve"}){
    warning;
    $msg .= "skip-name-resolve is not enabled in config file!! ";
}
my $msg2 = "(not found: ";
if($variables_found ne scalar keys %mysql_config){
    $msg .= $variables_found . " of ";
    foreach(sort @variables_not_found){
        $msg2 .= "$_/";
    }
    $msg2 =~ s/\/$//;
    $msg2 .= ")";
}
$msg .= (scalar keys %mysql_config) . " variables tested from config file '$config_file'";
if($variables_found ne scalar keys %mysql_config and scalar @variables_not_found > 0){
    warning if $warn_on_missing_variables;
    $msg .= " $msg2";
}
$msg .= ". $uptime_msg";
$msg .= ". MySQL Server Version $mysql_version";

quit $status, $msg;
