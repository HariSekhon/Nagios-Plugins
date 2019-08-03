#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-28 00:12:10 +0100 (Sun, 28 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check given HBase table(s) are online via the HBase Stargate Rest API Server

More simplistic than check_hbase_tables.pl program which uses the better programmatic Thrift API and has more levels of checks.

This plugin only checks to see if the given tables have regions listed on the cluster status page of the Stargate. Recommend to use check_hbase_tables.pl instead if possible

Tested on CDH 4.2, 4.3, 4.4, 4.5 and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

Known Limitations:

Known Issues/Limitations:

1. The HBase REST API doesn't seem to expose details on -ROOT- and .META. regions so the code only checks they are present (user specified tables are checked for online regions)
2. The HBase REST API doesn't distinguish between disabled and otherwise unavailable/nonexistent tables, instead use the thrift monitoring plugin check_hbase_tables.pl (aka check_hbase_tables_thrift.pl), or as a fallback the check_hbase_tables_jsp.pl for that distinction
3. The HBase REST Server will timeout the request for information if the HBase Master is down, you will see this as \"CRITICAL: '500 read timeout'\"";

$VERSION = "0.4.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::Simple '$ua';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

set_port_default(8080);

env_creds(["HBASE_STARGATE", "HBASE"], "HBase Stargate Rest API server");

my $tables;

%options = (
    %hostoptions,
    "T|tables=s" => [ \$tables, "Table(s) to check. This should be a list of user tables, not -ROOT- or .META. catalog tables which are checked additionally. If no tables are given then only -ROOT- and .META. are checked" ],
);

@usage_order = qw/host port tables/;
get_options();

$host  = validate_host($host);
$host  = validate_resolvable($host);
$port  = validate_port($port);
my @tables = ( "-ROOT-", ".META.");
push(@tables, split(/\s*,\s*/, $tables)) if defined($tables);
@tables or usage "no valid tables specified";
@tables = uniq_array @tables;
my $table;
foreach $table (@tables){
    if($table =~ /^(-ROOT-|\.META\.)$/){
    } else {
        $table = isDatabaseTableName($table) || usage "invalid table name $table given";
    }
}
vlog_option "tables", "[ " . join(" , ", @tables) . " ]";

my $url = "http://$host:$port/status/cluster";
vlog_option "url", $url;

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $content = curl $url, "HBase Stargate";
if($content =~ /\A\s*\Z/){
    quit "CRITICAL", "empty body returned from '$url'";
}

my @tables_online;
my @tables_not_available;
foreach $table (@tables){
    if($content =~ /^ {8}$table,[^,]*,[\w\.]+$/m){
        vlog2 "found table $table";
        push(@tables_online, $table);
    } else {
        vlog2 "table '$table' not found / available in output from Stargate";
        critical;
        push(@tables_not_available, $table);
    }
}
vlog2;

$msg = "HBase ";

sub print_tables($@){
    my $str = shift;
    my @arr = @_;
    if(@arr){
        @arr = uniq_array @arr;
        plural scalar @arr;
        $msg .= "table$plural $str: " . join(" , ", @arr) . " -- ";
    }
}

print_tables("not found/available", @tables_not_available);
print_tables("online",        @tables_online);

$msg =~ s/ -- $//;

quit $status, $msg;
