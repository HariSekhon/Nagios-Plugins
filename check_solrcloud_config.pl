#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2015-02-19 20:29:03 +0000 (Thu, 19 Feb 2015)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check SolrCloud config in ZooKeeper vs local copy

This is to check that the published SolrCloud config for a given collection matches what should be revision controlled 'downconfig' kept outside of ZooKeeper.

Checks:

- the given config name is linked to the given SolrCloud collection
- all files in given local config directory are present in SolrCloud ZooKeeper config
- all files in SolrCloud ZooKeeper config are found in the given local directory
- files present both locally and in SolrCloud ZooKeeper have matching contents

Tested on ZooKeeper 3.4.5 / 3.4.6 with SolrCloud 4.x

API / BUGS / Limitations:

Uses the Net::ZooKeeper perl module which leverages the ZooKeeper Client C API. Instructions for installing Net::ZooKeeper are found at https://github.com/harisekhon/nagios-plugins

1. Net::ZooKeeper API is slow, takes 5 seconds to create a connection object per ZooKeeper node specified (before it even tries to connect to ZooKeeper which happenes sub-second). Unfortunately this is a limitation of the Net::ZooKeeper API
2. Does not do a deep inspect to tell you what actual differences are between the configurations when not matching since this is a bit complicated both to compare and report on random type recursive structures. Currently only tells you that there are differences in the two file equivalents from local copy and ZooKeeper copy.
3. Since ZooKeeper znodes do not differentiate between files and directories, when checking znodes found in ZooKeeper for missing local files, znodes without children are compared to local files
";

$VERSION = "0.2";

use strict;
use warnings;
use IO::Socket;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils qw/:DEFAULT :time/;
#use HariSekhon::DiffHashes;
use HariSekhon::Solr;
use HariSekhon::ZooKeeper;
use Cwd 'abs_path';
use File::Find;

$DATA_READ_LEN = 1000000;

my $znode = "/collections";
my $base  = "/solr";
my $config_name;
my $conf_dir;

%options = (
    %zookeeper_options,
    %solroptions_collection,
    "n|config-name=s"   => [ \$config_name, "Config name to check the collection is linked against" ],
    "d|config-dir=s"    => [ \$conf_dir,    "Configuration directory of files containing solrconfig.xml, schema.xml etc to parse and compare to SolrCloud configuration" ],
    "b|base=s"          => [ \$base,        "Base Znode for Solr in ZooKeeper (default: /solr, should be just / for embedded or non-chrooted zookeeper)" ],
);
splice @usage_order, 6, 0, qw/collection config-name config-dir base list-collections/;

get_options();

my @hosts    = validate_hosts($host, $port);
$user        = validate_user($user)         if defined($user);
$password    = validate_password($password) if defined($password);
$collection  = validate_solr_collection($collection);
$znode       = validate_filename($base, 0, "base znode") . "$znode/$collection";
$znode       =~ s/\/+/\//g;
$znode       = validate_filename($znode, 0, "collection znode");
$config_name = validate_alnum($config_name, "config name");
$conf_dir    = abs_path(validate_dir($conf_dir, 0, "conf-dir"));

vlog2;
set_timeout();

$status = "UNKNOWN";

connect_zookeepers(@hosts);

check_znode_exists($znode);

my $data = get_znode_contents_json($znode);

my $link_age_secs = get_znode_age($znode);

$status = "OK";

my $configName = get_field2($data, "configName");
if($configName ne $config_name){
    quit "CRITICAL", "collection '$collection' is linked against config '$configName' instead of expectd '$config_name'";
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
    unless(check_znode_exists($znode)){
        push(@local_only_files, $filename);
        next;
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
        my $filename = $znode;
        $filename =~ s/^\/configs\/[^\/]+\///;
        vlog2 "checking ZooKeeper config file '$filename'";
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

if(@differing_files){
    critical;
    $msg .= scalar @differing_files . " differing files";
    $msg .= " (" . join(",", @differing_files) . "), " if $verbose;
}

if(@local_only_files){
    critical;
    $msg .= scalar @local_only_files . " files missing from ZooKeeper";
    $msg .= " (" . join(",", @local_only_files) . "), " if $verbose;
}

if(@zoo_only_files){
    critical;
    $msg .= scalar @zoo_only_files . " files only found in ZooKeeper but not local directory";
    $msg .= " (" . join(",", @zoo_only_files) . "), " if $verbose;
}

$msg .= scalar @files_checked . " files checked";
$msg .= ", last config link change " . sec2human($link_age_secs) . " ago";
$msg .= ", last config change " . sec2human($latest_change) . " ago";
$msg .=" |";
$msg .= " 'collection $collection last config change'=${latest_change}s";
$msg .= " 'collection $collection last config link change'=${link_age_secs}s";

vlog2;
quit $status, $msg;
