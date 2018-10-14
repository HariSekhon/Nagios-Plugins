#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-26 18:52:38 +0100 (Fri, 26 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check given HBase table(s) via the HBase Thrift Server API

See newer Python version check_hbase_table.py instead which works on newer versions of HBase

Checks:

1. Table exists
2. Table is enabled
3. Table has Columns
4. Table's regions are all assigned to regionservers
5. Outputs perfdata for the number of regions for the given table

Performance using the Thrift Server is much faster than trying to leverage the HBase API using JVM languages or the Rest API which lacks good structure for parsing and is slower as well.

Requires the CPAN Thrift perl module

HBase Thrift bindings were generated using Thrift 0.9.0 on CDH 4.3 (HBase 0.94.6-cdh4.3.0) CentOS 6.4 and placed under lib/Hbase

Tested on Cloudera CDH 4.4.0, 4.5.0 and Apache HBase 0.90, 0.92, 0.94, 0.95, 0.96, 0.98, 0.99, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

Known Issues/Limitations:

1. The HBase Thrift API doesn't seem to expose details on -ROOT- and .META. regions so the code only checks they are present, enabled and we can get Column descriptors for them (does check everything for user defined tables)
2. You will see Thrift timeout exceptions if your RegionServers are offline when trying to get Column descriptors or Region assignments (the Stargate handles this better - check_hbase_tables_stargate.pl):

CRITICAL: failed to get Column descriptors for table '.META.': Thrift::TException: TSocket: timed out reading 4 bytes from <hbase_thrift_server>:9090

3. The HBase Thrift server will not fully start up without the HBase Master being online, resulting in a connection refused error.
4. If the HBase Master is shut down after the Thrift server is already started, then you will get an error from the Thrift server similar to this:

CRITICAL: failed to get tables from HBase: TApplicationException: Internal error processing getTableNames
";

$VERSION = "0.7.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::HBase::Thrift;
use Data::Dumper;
use Thrift;
use Thrift::Socket;
use Thrift::BinaryProtocol;
use Thrift::BufferedTransport;
# Thrift generated bindings for HBase, provided in lib
use Hbase::Hbase;

# Thrift Server timeout is around 10 secs so we need to give a bit longer to get the more specific error rather than self terminating in the default 10 seconds
# update: calculated send + recv timeouts instead now
#set_timeout_default 20;

set_port_default(9090);

env_creds(["HBASE_THRIFT", "HBASE"], "HBase Thrift Server");

my $tables;
my $list_tables;

%options = (
    %hostoptions,
    "T|tables=s" => [ \$tables,      "Table(s) to check. Comma separated list of user tables, not -ROOT- or .META. catalog tables which are checked additionally. If no tables are specified then only -ROOT- and .META. are checked" ],
    "l|list"     => [ \$list_tables, "List HBase tables and exit" ]
);

@usage_order = qw/host port tables/;
get_options();

$host  = validate_host($host);
$port  = validate_port($port);
my @tables = qw/-ROOT- .META./;
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

vlog2;
set_timeout();

# this seems to actually be the timeout for the total connection so it should be just under the total execution time
my $send_timeout = minimum_value(($timeout*1000) - 1000, 1000);
my $recv_timeout = $send_timeout;
vlog2 sprintf("calculated Thrift send timeout as %s secs", $send_timeout / 1000);
vlog2 sprintf("calculated Thrift recv timeout as %s secs", $recv_timeout / 1000);
vlog2;

my $client = connect_hbase_thrift($host, $port, $send_timeout, $recv_timeout);
my @hbase_tables;

vlog2 "checking tables";
try {
    @hbase_tables = @{$client->getTableNames()};
};
catch_quit "failed to get tables from HBase";
@hbase_tables or quit "CRITICAL", "no tables found in HBase";
if($verbose >= 3){
    hr;
    print "found HBase tables:\n\n" . join("\n", @hbase_tables) . "\n";
    hr;
    print "\n";
}
if($list_tables){
    print "HBase Tables:\n\n" . join("\n", @hbase_tables) . "\n";
    exit $ERRORS{"UNKNOWN"};
}

my @tables_not_found;
my @tables_disabled;
my @tables_without_columns;
my @tables_without_regions;
my @tables_without_regionservers;
my @tables_with_unassigned_regions;
my @tables_ok;
my %table_regioncount;

sub check_table_enabled($){
    my $table = shift;
    my $state;
    # XXX: This seems to always return 1 unless the table is explicitly disabled, even returns 1 for tables that don't exist.
    vlog2 "checking table '$table' enabled/disabled";
    try {
        $state = $client->isTableEnabled($table);
    };
    catch {
        #if($table eq "-ROOT-" or $table eq ".META."){
        #    vlog2 "couldn't get table state for table '$table', might be newer version of HBase";
        #    return 0;
        #} else {
            quit "CRITICAL", "failed to get table state (enabled/disabled) for table '$table': $@->{message}";
        #}
    };
    if($state){
        vlog2 "table '$table' enabled";
    } else {
        vlog2 "table '$table' NOT enabled";
        critical;
        push(@tables_disabled, $table);
        return 0;
    }
    return 1;
}


sub check_table_columns($){
    my $table = shift;
    my $table_columns;
    vlog2 "checking table '$table' has column descriptors";
    try {
        $table_columns = $client->getColumnDescriptors($table);
    };
    catch_quit "failed to get Column descriptors for table '$table'";
    vlog3 "table '$table' columns: " . Dumper($table_columns);
    unless($table_columns){
        push(@tables_without_columns, $table);
        return 0;
    }
    vlog2 "table '$table' columns: " . join(",", sort keys %{$table_columns});
    return 1;
}


sub check_table_regions($){
    my $table = shift;
    my $table_regions;
    my @regionservers = ();
    vlog2 "checking table '$table' has regions";
    try {
        $table_regions = $client->getTableRegions($table);
    };
    catch_quit "failed to get regions for table '$table'";
    $table_regions or quit "UNKNOWN", "failed to get regions for table '$table'";
    vlog3 "table '$table' regions: " . Dumper($table_regions);
    unless(@{$table_regions}){
        push(@tables_without_regions, $table);
        return 0;
    }
    $table_regioncount{$table} = scalar @{$table_regions};
    vlog2 "table '$table' regions: $table_regioncount{$table}";
    vlog2 "checking table '$table' regions are all assigned to regionservers";
    foreach my $ref (@{$table_regions}){
        if(defined($ref->serverName) and $ref->serverName){
            push(@regionservers, $ref->serverName);
        } else {
            vlog2 "table '$table' region '$ref->name' is unassigned to any regionserver!";
            push(@tables_with_unassigned_regions, $table);
        }
    }
    if(@regionservers){
        @regionservers = uniq_array @regionservers;
        vlog2 "table '$table' regionservers: " . join(",", @regionservers);
    } else {
        vlog2 "table '$table' has NO regionservers!";
        push(@tables_without_regionservers, $table);
        return 0;
    }
    return 1;
}


sub check_table($){
    my $table = shift;
    check_table_enabled($table) and
    check_table_columns($table) and
    check_table_regions($table) and
    push(@tables_ok, $table);
}

foreach $table (@tables){
    # XXX: Thrift API doesn't give us region info on -ROOT- and .META. so running check_table* individually without check_table_regions
    if(grep { $table eq $_ } qw/-ROOT- .META./){
        check_table_enabled($table) and
        check_table_columns($table) and
        push(@tables_ok, $table);
    } else {
        unless(grep { $table eq $_ } @hbase_tables){
            vlog2 "table '$table' not found in list of returned HBase tables";
            critical;
            push(@tables_not_found, $table);
            next;
        }
        check_table($table);
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

print_tables("not found",               @tables_not_found);
print_tables("disabled",                @tables_disabled);
print_tables("with no columns",         @tables_without_columns);
print_tables("without regions",         @tables_without_regions);
print_tables("without regionservers",   @tables_without_regionservers);
print_tables("with unassigned regions", @tables_with_unassigned_regions);
print_tables("ok",                      @tables_ok);

$msg =~ s/ -- $//;
if(keys %table_regioncount){
    $msg .= " |";
    foreach $table (sort keys %table_regioncount){
        $msg .= " '$table regions'=$table_regioncount{$table}";
    }
}

quit $status, $msg;
