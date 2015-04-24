#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-27 17:48:22 +0000 (Sun, 27 Oct 2013)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#  

# TODO: add Kerberos support equivalent to curl --negotiate -u : -iL http://....

$DESCRIPTION = "Nagios Plugin to check HDFS files/directories or writable via WebHDFS API or HttpFS server

Checks:

- File/directory existence and one or more of the following:
    - type: file or directory
    - owner/group
    - permissions
    - size / empty
    - block size
    - replication factor
    - last accessed time
    - last modified time

OR

- HDFS writable - writes a small unique canary file to hdfs:///tmp to check that HDFS is fully available and not in Safe mode (implies enough DataNodes have checked in after startup to achieve 99.9% block availability by default). Deletes the canary file as part of the test to avoid build up of small files.

If you are running NameNode HA then you should be pointing this program to the HttpFS server and not one NameNode directly to avoid hitting the Standby NameNode by mistake or requiring extra logic to determine the Active NameNode first which may take additional round trips.

Tested on CDH 4.5 and HDP 2.2
";

$VERSION = "0.3.3";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS 'decode_json';
use LWP::UserAgent;
use Sys::Hostname;
use Time::HiRes;

my $ua = LWP::UserAgent->new( 'requests_redirectable' => ['GET', 'PUT'] );

$ua->agent("Hari Sekhon $progname version $main::VERSION");

if($progname =~ /httpfs/i){
    set_port_default(14000);
    env_creds(["HADOOP_HTTPFS", "HADOOP"], "Hadoop HttpFS Server");
} else {
    set_port_default(50070);
    env_creds(["HADOOP_NAMENODE", "HADOOP"], "Hadoop NameNode");
}

my $write;
my $path;
my @valid_types = qw/FILE DIRECTORY/;
my %file_checks = (
                    "type"          => undef,
                    "zero"          => 0,
                    "non-zero"      => 0,
                    "owner"         => undef,
                    "group"         => undef,
                    "permission"    => undef,
                    "size"          => 0,
                    "blockSize"     => undef,
                    "replication"   => undef,
                    "last accessed" => undef,
                    "last modified" => undef,
);

%options = (
    %hostoptions,
    #"u|user=s"          => [ \$user,                          "User to connect as (\$USERNAME, \$USER). Tries to determine system user running as if it doesn't find one of these environment vars)" ],
    "u|user=s"          => $useroptions{"u|user=s"},
    "w|write"           => [ \$write,                         "Write unique canary file to hdfs:///tmp to check HDFS is writable and not in Safe mode" ],
    "p|path=s"          => [ \$path,                          "File or directory to check exists in Hadoop HDFS"  ],
    "T|type=s"          => [ \$file_checks{"type"},           "'FILE' or 'DIRECTORY' (default: 'FILE')" ],
    "o|owner=s"         => [ \$file_checks{"owner"},          "Owner name" ],
    "g|group=s"         => [ \$file_checks{"group"},          "Group name" ],
    "e|permission=s"    => [ \$file_checks{"permission"},     "Permission octal mode" ],
    "Z|zero"            => [ \$file_checks{"zero"},           "Additional check that file is empty"     ],
    "S|size=s"          => [ \$file_checks{"size"},           "Minimum size of file" ],
    "B|blockSize=s"     => [ \$file_checks{"blockSize"},      "Blocksize to expect"  ],
    "R|replication=s"   => [ \$file_checks{"replication"},    "Replication factor" ],
    "a|last-accessed=s" => [ \$file_checks{"last accessed"},  "Last-accessed time maximum in seconds" ],
    "m|last-modified=s" => [ \$file_checks{"last modified"},  "Last-modified time maximum in seconds" ],
);

if($progname =~ /write/i){
    $write = 1;
    %options = ( %hostoptions );
} elsif($progname =~ /file/i){
    delete $options{"w|write"};
}

@usage_order = qw/host port user write path type owner group permission zero size blocksize replication last-accessed last-modified/;
get_options();

$host = validate_host($host);
$port = validate_port($port);

my $canary_file;
my $canary_contents;

if($write){
    vlog_options "write", "true";
    $canary_contents = random_alnum(20);
    $canary_file = "/tmp/$progname.canary." . hostname . "." . Time::HiRes::time . "." . substr($canary_contents, 0, 10);
    $canary_file = validate_filename($canary_file, 0, "canary file");
    if($path){
        usage "cannot specify --path with --write";
    }
    foreach(keys %file_checks){
        next if $_ eq "type";
        $file_checks{$_} and usage "cannot specify file checks with --write";
    }
} else {
    $path = validate_filename($path, 0, "path");

    if($file_checks{"zero"} and $file_checks{"size"}){
        usage "--zero and --size are mutually exclusive";
    }

    if(defined($file_checks{"type"}) and $file_checks{"type"}){
        $file_checks{"type"} = uc $file_checks{"type"};
        grep { $file_checks{"type"} eq $_ } @valid_types or usage "invalid type: must be one of " . join(",", @valid_types);
    }

    if(defined($file_checks{"type"}) and $file_checks{"type"} eq "DIRECTORY" and $file_checks{"size"}){
        usage "cannot specify non-zero for a directory, directory length is always zero";
    }

    if(defined($file_checks{"type"}) and $file_checks{"type"} eq "DIRECTORY" and $file_checks{"replication"}){
        usage "directories cannot have replication factor other than zero";
    }

    foreach(sort keys %file_checks){
        vlog_options $_, $file_checks{$_} if defined($file_checks{$_});
    }
}

vlog2;
set_timeout();

$status = "UNKNOWN";

# inherit HADOOP*_USERNAME, HADOOP*_USER vars as more flexible
$user = (getpwuid($>))[0] unless $user;
if(not $user or $user =~ /&/){
    quit "UNKNOWN", "couldn't determine user to send to NameNode from environment variables (\$USER, \$USERNAME) or getpwuid() call";
}
vlog_options "user", $user;
vlog2;

my $webhdfs_uri = 'webhdfs/v1';
my $ip  = validate_resolvable($host);
vlog2 "resolved $host to $ip\n";

my $op = "GETFILESTATUS";
if($write){
    $op   = "CREATE&overwrite=false";
    $path = $canary_file;
}
$path =~ s/^\///;
my $url  = "http://$ip:$port/$webhdfs_uri/$path?user.name=$user&op="; # uppercase OP= only works on WebHDFS, not on HttpFS

$ua->show_progress(1) if $debug;

sub check_response($){
    my $response = shift;
    my $content  = $response->content;
    chomp $content;
    vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
    vlog2 "http code: " . $response->code;
    vlog2 "message: " . $response->message . "\n";
    if(!$response->is_success){
        my $err = $response->code . " " . $response->message;
        try {
            my $json = decode_json($content);
            if(defined($json->{"RemoteException"}->{"javaClassName"})){
                if($json->{"RemoteException"}->{"javaClassName"} eq "java.io.FileNotFoundException"){
                    $err = "";
                } else {
                    $err .= ": " . $json->{"RemoteException"}->{"javaClassName"};
                }
            }
            if(defined($json->{"RemoteException"}->{"message"})){
                $err .= ": " if $err;
                $err .= $json->{"RemoteException"}->{"message"};
            }
        };
        quit "CRITICAL", $err;
    }
}

if($write){
    vlog2 "writing canary file '$canary_file'";
    vlog2 "PUT $url$op";
    my $response = $ua->put("$url$op", Content => $canary_contents, "Content-Type" => "application/octet-stream");
    check_response($response);
    $status = "OK";
    $msg    = "HDFS canary file written";
    $op     = "OPEN&offset=0&length=1024";
    vlog2 "reading canary file back";
    $response = $ua->get("$url$op");
    check_response($response);
    unless($response->content eq $canary_contents){
        quit "CRITICAL", "mismatch on reading back canary file's contents (expected: '$canary_contents', got: '" . $response->content . "')";
    }
    $msg .= ", contents read back and verified successfully";
    $op   = "DELETE&recursive=false";
    vlog2 "deleting canary file";
    $response = $ua->delete("$url$op");
    check_response($response);
} else {
    vlog2 "GET $url$op";
    my $response = $ua->get("$url$op");
    check_response($response);
    my $json;
    try {
        $json = decode_json($response->content);
    };
    catch_quit "failed to decode json response from $host";
    $status = "OK";
    $msg = "'/$path' exists";
    foreach(qw/type owner group permission blockSize replication/){
        defined($json->{"FileStatus"}->{$_}) or quit "UNKNOWN", "field $_ not found for '$path'. $nagios_plugins_support_msg";
        $msg .= " $_=" . $json->{"FileStatus"}->{$_};
        if(defined($file_checks{$_})){
            unless($json->{"FileStatus"}->{$_} eq $file_checks{$_}){
                critical;
                $msg .= " (expected: '$file_checks{$_}')";
            }
        }
    }
    my $size;
    defined($json->{"FileStatus"}->{"length"}) or quit "UNKNOWN", "length field not found for '$path'. $nagios_plugins_support_msg";
    $size = $json->{"FileStatus"}->{"length"};
    $msg .= " size=$size";
    if($file_checks{"zero"}){
        unless($size eq 0){
            critical;
            $msg .= " (expected: zero)";
        }
    } elsif($file_checks{"size"}){
        unless($size >= $file_checks{"size"}){
            critical;
            $msg .= " (expected: >= $file_checks{size})";
        }
    }
    defined($json->{"FileStatus"}->{"accessTime"}) or quit "UNKNOWN", "accessTime field not found for '$path'. $nagios_plugins_support_msg";
    my $last_accessed      = int($json->{"FileStatus"}->{"accessTime"} / 1000);
    my $last_accessed_diff = time - $last_accessed;
    $msg .= " accessTime=$last_accessed";

    if($file_checks{"last accessed"}){
        unless($last_accessed_diff <= $file_checks{"last accessed"}){
            critical;
            $msg .= " ($last_accessed_diff>" . $file_checks{"last accessed"} . " secs ago)";
        }
    }

    defined($json->{"FileStatus"}->{"modificationTime"}) or quit "UNKNOWN", "modificationTime field not found for '$path'. $nagios_plugins_support_msg";
    my $last_modified      = int($json->{"FileStatus"}->{"modificationTime"} / 1000);
    my $last_modified_diff = time - $last_modified;
    $msg .= " modifiedTime=$last_modified";

    if($file_checks{"last modified"}){
        unless($last_modified_diff <= $file_checks{"last modified"}){
            critical;
            $msg .= " ($last_modified_diff>" . $file_checks{"last modified"} . " secs ago)";
        }
    }
}

quit $status, $msg;
