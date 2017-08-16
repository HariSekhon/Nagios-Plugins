#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2014-04-22 21:40:03 +0100 (Tue, 22 Apr 2014)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

# http://www-01.ibm.com/support/knowledgecenter/SSPT3X_2.1.2/com.ibm.swg.im.infosphere.biginsights.admin.doc/doc/rest_access_file_admin.html?lang=en

$DESCRIPTION = "Nagios Plugin to check IBM BigInsights File/Directory on HDFS or GPFS via BigInsights Console REST API

Checks:

- File/directory existence
- check whether the given path is a file or directory

Directory Checks:

The following additional checks may be applied to directories. Not available for files at this time due to limitation of BigInsights Console API only returning metadata for directories:

- owner/group
- permissions
- size / empty
- last accessed time
- last modified time

Tested on IBM BigInsights Console 2.1.2.0";

$VERSION = "0.2.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use HariSekhon::IBM::BigInsights;
use Data::Dumper;
use POSIX 'floor';

$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $path;
my @valid_types = qw/FILE DIRECTORY/;
my %file_checks = (
                    "type"          => undef,
                    "empty"         => undef,
                    "owner"         => undef,
                    "group"         => undef,
                    "permission"    => undef,
                    "size"          => undef,
                    #"blockSize"     => undef,
                    #"replication"   => undef,
                    "last accessed" => undef,
                    "last modified" => undef,
);

%options = (
    %biginsights_options,
    "path=s"            => [ \$path,                          "Full path to File or directory to check exists in filesystems (HDFS/GPFS)"  ],
    "T|type=s"          => [ \$file_checks{"type"},           "'FILE' or 'DIRECTORY' (default: 'FILE')" ],
    "o|owner=s"         => [ \$file_checks{"owner"},          "Owner name" ],
    "g|group=s"         => [ \$file_checks{"group"},          "Group name" ],
    "e|permission=s"    => [ \$file_checks{"permission"},     "Permission string to expect" ],
    "s|size=s"          => [ \$file_checks{"size"},           "Minimum size of file" ],
    "E|empty"           => [ \$file_checks{"empty"},          "Checks directory is empty" ],
#    "B|blockSize=s"     => [ \$file_checks{"blockSize"},      "Blocksize to expect"  ],
#    "R|replication=s"   => [ \$file_checks{"replication"},    "Replication factor" ],
    "a|last-accessed=s" => [ \$file_checks{"last accessed"},  "Last-accessed time maximum in seconds" ],
    "m|last-modified=s" => [ \$file_checks{"last modified"},  "Last-modified time maximum in seconds" ],
);
splice @usage_order, 4, 0, qw/path type owner group permission size empty blocksize replication last-accessed last-modified/;

get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password);
validate_ssl();

# ============================================================================ #
# taken from check_hadoop_hdfs_file_webhdfs.pl
$path       = validate_filename($path, "path");
$path =~ /^\// or usage "--path must be a full path starting with a slash /";

if($file_checks{"empty"} and $file_checks{"size"}){
    usage "--empty and --size are mutually exclusive";
}

if(defined($file_checks{"type"}) and $file_checks{"type"}){
    $file_checks{"type"} = uc $file_checks{"type"};
    grep { $file_checks{"type"} eq $_ } @valid_types or usage "invalid type: must be one of " . join(",", @valid_types);
}

#if(defined($file_checks{"type"}) and $file_checks{"type"} eq "DIRECTORY" and $file_checks{"replication"}){
#    usage "directories cannot have replication factor other than zero";
#}
#
foreach(sort keys %file_checks){
    if(defined($file_checks{$_})){
        vlog_option $_, $file_checks{$_};
        next if $_ eq "type";
        if((not defined($file_checks{"type"})) or $file_checks{"type"} ne "DIRECTORY"){
            usage "checks can only be specified for directories since the BigInsights Console API only returns metadata for directories. If a directory is expected then make it explicit with -T DIRECTORY"
        }
    }
}

# ============================================================================ #

vlog2;
set_timeout();

my $url_prefix = "$protocol://$host:$port";

$status = "OK";

# workaround to BigInsights returning contents instead of metadata for files
sub curl_biginsights_err_handler_minimal($){
    my $response = shift;
    my $content  = $response->content;
    my $json;
    my $additional_information = "";
    if($json = isJson($content)){
        vlog3(Dumper($json));
        if(defined($json->{"result"}{"error"})){
            quit "CRITICAL", "Error: " . $json->{"result"}{"error"};
        }
    }
    unless($response->code eq "200"){
        quit "CRITICAL", $response->code . " " . $response->message . $additional_information;
    }
    # since contents are returned for files and files may well be blank we cannot use this check and must rely on HTTP code
    #unless($content){
    #    quit "CRITICAL", "blank content returned from by BigInsights Console";
    #}
}

$path =~ s/^\///;
# need to pass more minimal error handler, not demanding JSON since file contents are returned instead of metadata
#curl_biginsights "/dfs/$path?format=json&download=false", $user, $password;
#
# XXX: BUG in BigInsights Console - download=false doesn't seem to have any effect
# XXX: BUG in BigInsights Console - offset is acting as length with higher preference to length, seek param replaces offset in 2.1.x and seek does work but then offset should do nothing not act as length
my $content = curl "$protocol://$host:$port/$api/dfs/$path?format=json&download=false&length=512", "IBM BigInsights Console", $user, $password, \&curl_biginsights_err_handler_minimal;

# assume directory if json metadata returned as API only gives metadata for directories, but also checking for directory field and also that directory field is set to true
if($json = isJson($content) and defined($json->{"directory"}) and $json->{"directory"}){
    $msg = "directory '/$path' exists";
    if(defined($file_checks{"type"}) and $file_checks{"type"} eq "FILE"){
        critical;
        $msg .= " (expected file)";
    }
    $msg .= ",";
#    foreach(qw/type owner group permission blockSize replication/){
    foreach(qw/owner group permission/){
        $msg .= " $_=" . get_field($_);
        if(defined($file_checks{$_})){
            unless(get_field($_) eq $file_checks{$_}){
                critical;
                $msg .= " (expected: '$file_checks{$_}')";
            }
        }
    }
    my $size = get_field("size");
    $msg .= " size=$size";
    if($file_checks{"empty"}){
        unless($size eq 0){
            critical;
            $msg .= " (expected: empty)";
        }
    } elsif($file_checks{"size"}){
        unless($size >= $file_checks{"size"}){
            critical;
            $msg .= " (expected: >= $file_checks{size})";
        }
    }
    my $last_accessed      = floor(get_field("accessTime") / 1000);
    my $last_accessed_diff = time - $last_accessed;
    $msg .= " accessTime=$last_accessed";

    if($file_checks{"last accessed"}){
        unless($last_accessed_diff <= $file_checks{"last accessed"}){
            critical;
            $msg .= " ($last_accessed_diff>" . $file_checks{"last accessed"} . " secs ago)";
        }
    }

    my $last_modified      = int(get_field("modified") / 1000);
    my $last_modified_diff = time - $last_modified;
    $msg .= " modifiedTime=$last_modified";

    if($file_checks{"last modified"}){
        unless($last_modified_diff <= $file_checks{"last modified"}){
            critical;
            $msg .= " ($last_modified_diff>" . $file_checks{"last modified"} . " secs ago)";
        }
    }
} else {
    $msg = "file '/$path' exists";
    if(defined($file_checks{"type"}) and $file_checks{"type"} eq "DIRECTORY"){
        critical;
        $msg .= " (expected directory)";
    }
}

quit $status, $msg;
