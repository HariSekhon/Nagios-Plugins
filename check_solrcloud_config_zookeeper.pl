#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-19 20:29:03 +0000 (Thu, 19 Feb 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check SolrCloud config in ZooKeeper vs local copy

This is to check that the published SolrCloud config for a given collection matches what should be revision controlled 'downconfig' kept outside of ZooKeeper.

Checks:

- the given config name is linked to the given SolrCloud collection (optional)
- all files in given local config directory are present in SolrCloud ZooKeeper config
- all files in SolrCloud ZooKeeper config are found in the given local directory
- files present both locally and in SolrCloud ZooKeeper have matching contents
- in verbose mode shows which files are differing or missing between local Solr config vs ZooKeeper SolrCloud config
- outputs the time since last config change in ZooKeeper as well as the last config linking change in ZooKeeper

Tested on ZooKeeper 3.4.5 / 3.4.6 with SolrCloud 4.7, 4.10, 5.4, 5.5, 6.0, 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 7.0, 7.1

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. Does not do a deep inspect to tell you what actual differences are between the configurations when not matching since this is a bit complicated both to compare and report on random type recursive structures. Currently only tells you that there are differences in the two file equivalents from local copy and ZooKeeper copy.
3. Since ZooKeeper znodes do not differentiate between files and directories, when checking znodes found in ZooKeeper for missing local files, znodes without children are compared to local files
";

$VERSION = "0.3.6";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
#use HariSekhon::DiffHashes;
use HariSekhon::ZooKeeper;
use HariSekhon::Solr;
use Cwd 'abs_path';
use File::Find;

$DATA_READ_LEN = 1000000;

set_timeout_default(20);

my $znode = "/collections";
my $base  = "/solr";
my $config_name;
my $conf_dir;

%options = (
    %zookeeper_options,
    %solroptions_collection,
    "d|config-dir=s"    => [ \$conf_dir,    "Config directory of files containing solrconfig.xml, schema.xml etc to parse and compare to SolrCloud configuration" ],
    "n|config-name=s"   => [ \$config_name, "Config name to check the collection is linked against (optional)" ],
    "b|base=s"          => [ \$base,        "Base Znode for Solr in ZooKeeper (default: /solr, should be just / for embedded or non-chrooted zookeeper)" ],
);
splice @usage_order, 6, 0, qw/collection config-dir config-name base list-collections/;

get_options();

my @hosts    = validate_hosts($host, $port);
$user        = validate_user($user)         if defined($user);
$password    = validate_password($password) if defined($password);
$collection  = validate_solr_collection($collection);
$znode       = validate_base_and_znode($base, "$znode/$collection", "collection");
$config_name = validate_alnum($config_name, "config name") if defined($config_name);
$conf_dir    = abs_path(validate_dir($conf_dir, "conf-dir"));

vlog2;
set_timeout();

$status = "UNKNOWN";

my $start = time;

connect_zookeepers(@hosts);

check_znode_exists($znode);

my $data = get_znode_contents_json($znode);

my $link_age_secs = get_znode_age($znode);

$status = "OK";

my $configName = get_field2($data, "configName");
if($config_name and $configName ne $config_name){
    quit "CRITICAL", "collection '$collection' is linked against config '$configName' instead of expected '$config_name'";
}

my $config_znode = "$base/configs/$configName";
$config_znode =~ s/\/+/\//g;

vlog2;
check_znode_exists($config_znode);

my $latest_change;
my @differing_files;
my @files_checked;
my @local_only_files;
my @zoo_only_files;

vlog2;
sub check_file(){
    my $filename = $File::Find::name;
    #my $filename = $_;
    $filename =~ s/^$conf_dir\/?//;
    return unless $filename;
    return if (-d "$conf_dir/$filename");
    vlog2 "checking file '$filename'";
    push(@files_checked, $filename);
    my $file_handle = open_file "$conf_dir/$filename";
    local $/=undef;
    my $file_data   = <$file_handle>;
    #vlog3 "'$filename' file data:\n\n$file_data\n\n";
    # not all the files are XML
    #isXml($file_data) or quit "UNKNOWN", "invalid/empty XML in '$filename'";
    my $znode = "$config_znode/$filename";
    $znode =~ s/\/+/\//g;
    unless(check_znode_exists($znode, 1)){
        push(@local_only_files, $filename);
        return;
    }
    my $file_cloud_data = get_znode_contents($znode);
    $file_cloud_data =~ s/\r//g;
    vlog2 "checking whitespace trimmed contents of both files";
    #print "contents <" . trim($file_data) . ">\n";
    #print "contents <" . trim($file_cloud_data) . ">\n";
    if(trim($file_data) eq trim($file_cloud_data)){
        vlog2 "$filename matches";
    } else {
        vlog2 "$filename differs";
        push(@differing_files, $filename);
    }
    vlog2;
}
find({ "wanted" => \&check_file, "untaint" => 1}, $conf_dir);

# for prototype checking for recursion
sub check_zookeeper_dir($);

my $zookeeper_file_count = 0;
sub check_zookeeper_dir($){
    my $znode = shift;
    $znode =~ s/\/+/\//g;
    $znode =~ s/\/$//;
    my @children = $zkh->get_children($znode);
    #print "znode '$znode' children " . join(",", @children) . "\n";
    if(@children){
        foreach(@children){
            check_zookeeper_dir("$znode/$_");
        }
    } else {
        $zookeeper_file_count++;
        my $filename = $znode;
        $filename =~ s/^$base\/?configs\/[^\/]+\///;
        $filename =~ s/\/+/\//g;
        vlog2 "checking ZooKeeper config file '$znode'";
        my $file_age = get_znode_age($znode);
        if(not defined($latest_change) or $latest_change < $file_age){
            $latest_change = $file_age;
        }
        unless(grep { $filename eq $_ } @files_checked){
            vlog2 "file '$filename' not found in files checked";
            push(@zoo_only_files, $filename);
        }
    }
}
check_zookeeper_dir($config_znode);

my $differing_files  = scalar @differing_files;
my $local_only_files = scalar @local_only_files;
my $zoo_only_files   = scalar @zoo_only_files;
if(@differing_files){
    critical;
    plural $differing_files;
    $msg .= "$differing_files differing file$plural";
    $msg .= " (" . join(",", @differing_files) . ")" if $verbose;
    $msg .= ", ";
}

if(@local_only_files){
    critical;
    $msg .= "$local_only_files file$plural missing in ZooKeeper";
    $msg .= " (" . join(",", @local_only_files) . ")" if $verbose;
    $msg .= ", ";
}

if(@zoo_only_files){
    critical;
    $msg .= "$zoo_only_files file$plural only found in ZooKeeper but not local directory";
    $msg .= " (" . join(",", @zoo_only_files) . ")" if $verbose;
    $msg .= ", ";
}

my $timer_secs = time - $start;
$msg .= scalar @files_checked . " files checked vs SolrCloud collection '$collection' ZooKeeper config '$configName'";
$msg .= ", check took $timer_secs secs" if $verbose;
$msg .= ", last config link change " . sec2human($link_age_secs) . " ago";
$msg .= ", last config change " . sec2human($latest_change) . " ago";
$msg .=" |";
$msg .= " 'local file count'=" . scalar @files_checked;
$msg .= " 'zookeeper file count'=$zookeeper_file_count";
$msg .= " 'differing file count'=$differing_files;;1";
$msg .= " 'files only in local conf dir'=$local_only_files;;1";
$msg .= " 'files only in zookeeper'=$zoo_only_files;;1";
$msg .= " 'time taken for check'=${timer_secs}s";
$msg .= " 'last config link change'=${link_age_secs}s";
$msg .= " 'last config change'=${latest_change}s";

vlog2;
quit $status, $msg;
