#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-28 00:12:10 +0100 (Sun, 28 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check given HBase table(s) are online via the HBase Stargate Rest API Server

More simplistic check than the check_hbase_tables.pl program which uses the better programmatic Thrift API and has more levels of checks. This plugin only checks to see if the given tables have regions listed on the cluster status page of the Stargate"; 

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;

my $default_port = 20550;
$port = $default_port;

my $tables;

%options = (
    "H|host=s"         => [ \$host,         "HBase Stargate Rest API server address to connect to" ],
    "P|port=s"         => [ \$port,         "HBase Stargate Rest API server port to connect to (defaults to $default_port)" ],
    "T|tables=s"       => [ \$tables,       "Table(s) to check. This should be a list of user tables, not -ROOT- or .META. catalog tables which are checked additionally. If no tables are given then only -ROOT- and .META. are checked" ],
);

@usage_order = qw/host port tables/;
get_options();

$host  = validate_hostname($host);
$port  = validate_port($port);
my @tables = ( "-ROOT-", ".META.");
push(@tables, split(/\s*,\s*/, $tables)) if defined($tables);
@tables or usage "no valid tables specified";
@tables = uniq_array @tables;
my $table;
foreach $table (@tables){
    if($table =~ /^(-ROOT-|\.META\.)$/){
    } else {
        $table = isDatabaseTableName($table) or usage "invalid table name $table given";
    }
}
vlog_options "tables", "[ " . join(" , ", @tables) . " ]";

my $url = "http://$host:$port/status/cluster";
vlog_options "url", $url;

vlog2;
set_timeout();

$status = "OK";

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");

vlog2 "querying Stargate";
my $res = $ua->get($url);
vlog2 "got response";
my $status_line  = $res->status_line;
vlog2 "status line: $status_line";
my $content = my $content_single_line = $res->content;
vlog3 "\ncontent:\n\n$content\n";
$content_single_line =~ s/\n/ /g;
vlog2;

unless($res->code eq 200){
    quit "CRITICAL", "'$status_line'";
}
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
if(@tables_not_available){
    @tables_not_available = uniq_array @tables_not_available;
    plural @tables_not_available;
    $msg .= "table$plural not available: " . join(" , ", @tables_not_available) . " , ";
}
if(@tables_online){
    plural @tables_online;
    $msg .= "table$plural online: " . join(" , ", @tables_online);
}
$msg =~ s/ , $//;

quit $status, $msg;
