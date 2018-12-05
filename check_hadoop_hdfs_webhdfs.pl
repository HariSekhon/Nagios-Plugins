#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-27 17:48:22 +0000 (Sun, 27 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

our $DESCRIPTION = "Nagios Plugin to check HDFS files/directories or writable via WebHDFS API or HttpFS server

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

- HDFS writable - writes a small unique canary file to hdfs:///tmp to check that HDFS is fully available and not in Safe mode (implies enough DataNodes have checked in after startup to achieve 99.9% block availability by default). Deletes the canary file as part of the test to avoid build up of small files. However, if the operation times out on read back or delete then small files will be left in HDFS /tmp, so you should run a periodic cleanup of those (see hadoop_hdfs_retention_policy.pl in https://github.com/harisekhon/devops-perl-tools).

Supports Kerberos authentication but must have a valid kerberos ticket and must use the FQDN of the server, not an IP address and not a short name, otherwise you will get a \"401 Authentication required\" error.

Tested on CDH 4.5, HDP 2.2, Apache Hadoop 2.3, 2.4, 2.5, 2.6, 2.7, 2.8
";

$VERSION = "0.5.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use JSON::XS 'decode_json';
# pulls in LWP::Authen::Negotiate if available (cpan'd in Makefile) and uses the kinit'd TGT if found
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
                    "type"          => "",
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
    "u|user=s"          => $useroptions{"u|user=s"},
    "w|write"           => [ \$write,                         "Write unique canary file to hdfs:///tmp to check HDFS is writable and not in Safe mode" ],
    "p|path=s"          => [ \$path,                          "File or directory to check exists in Hadoop HDFS" ],
    "T|type=s"          => [ \$file_checks{"type"},           "'FILE' or 'DIRECTORY' (default: 'FILE')" ],
    "o|owner=s"         => [ \$file_checks{"owner"},          "Owner name" ],
    "g|group=s"         => [ \$file_checks{"group"},          "Group name" ],
    "e|permission=s"    => [ \$file_checks{"permission"},     "Permission octal mode" ],
    "Z|zero"            => [ \$file_checks{"zero"},           "Additional check that file is empty" ],
    "S|size=s"          => [ \$file_checks{"size"},           "Minimum size of file" ],
    "B|blockSize=s"     => [ \$file_checks{"blockSize"},      "Blocksize to expect in bytes" ],
    "R|replication=s"   => [ \$file_checks{"replication"},    "Replication factor" ],
    "a|last-accessed=s" => [ \$file_checks{"last accessed"},  "Last-accessed time maximum in seconds" ],
    "m|last-modified=s" => [ \$file_checks{"last modified"},  "Last-modified time maximum in seconds" ],
);
$options{"u|user=s"}[1] .= ". If not specified and none of those environment variables are found, tries to determine system user this program is running as. If using Kerberos must ensure this matches the keytab principal";
$options{"H|host=s"}[1] .= ". Must use FQDN if using Kerberos";
if($progname =~ /webhdfs/i){
    $DESCRIPTION =~ s/Tested on/Supports NameNode HA if specifying more than one NameNode will work like the standard HDFS client and failover to the other instead of returning errors such as \"403 Forbidden: org.apache.hadoop.ipc.StandbyException: Operation category READ is not supported in state standby\". This however is not the optimal method as it results in 2 network round trips in case the first attempted NameNode is not the Active one (this is how HDFS client works too) and may extend the runtime of this plugin, making it more likely to time out.

In a NameNode HA configuration it's more correct to run an HttpFS server as a WebHDFS frontend and specify that as the --host instead - it's the same protocol but on a different port. The HttpFS server then handles the failover upstream resulting in fewer network trips for this plugin making it less likely to time out.

Tested on/;
    $options{"H|host=s"}[1] .= ". Can specify both NameNodes in HDFS HA setup comma delimited to avoid \"Operation category READ is not supported in state standby\" type errors. However this can result in 2 round trips and it is more efficient to use an HttpFS server instead";
}

if($progname =~ /write/i){
    $write = 1;
    %options = ( %hostoptions );
} elsif($progname =~ /file/i){
    delete $options{"w|write"};
}

@usage_order = qw/host port user write path type owner group permission zero size blocksize replication last-accessed last-modified/;
get_options();

my @hosts;
if($progname =~ /webhdfs/i and $host and $host =~ /,/){
    @hosts = split(/\s*,\s*/, $host);
    foreach(my $i = 0; $i < scalar @hosts; $i++){
        $hosts[$i] = validate_host($hosts[$i]);
    }
    @hosts = uniq_array2 @hosts;
} else {
    $hosts[0] = validate_host($host);
}
$port = validate_port($port);

my $canary_file;
my $canary_contents;

if($write){
    vlog_option "write", "true";
    $canary_contents = random_alnum(20);
    $canary_file = "/tmp/$progname.canary." . hostname . "." . Time::HiRes::time . "." . substr($canary_contents, 0, 10);
    $canary_file = validate_filename($canary_file, "canary file");
    if($path){
        usage "cannot specify --path with --write";
    }
    $path = $canary_file;
    foreach(keys %file_checks){
        next if $_ eq "type";
        $file_checks{$_} and usage "cannot specify file checks with --write";
    }
} else {
    $path = validate_dirname($path, "path");

    if($file_checks{"zero"} and $file_checks{"size"}){
        usage "--zero and --size are mutually exclusive";
    }

    if($file_checks{"type"}){
        $file_checks{"type"} = uc $file_checks{"type"};
        grep { $file_checks{"type"} eq $_ } @valid_types or usage "invalid type: must be one of " . join(",", @valid_types);
    }

    if($file_checks{"type"} eq "DIRECTORY" and $file_checks{"size"}){
        usage "cannot specify size for a directory, directory length is always zero";
    }

    if($file_checks{"type"} eq "DIRECTORY" and $file_checks{"replication"}){
        usage "directories cannot have replication factor other than zero";
    }

    foreach(sort keys %file_checks){
        vlog_option $_, $file_checks{$_} if defined($file_checks{$_});
    }
}

vlog2;
set_timeout();

$status = "OK";

# inherit HADOOP*_USERNAME, HADOOP*_USER vars as more flexible
$user = (getpwuid($>))[0] unless $user;
if(not $user or $user =~ /&/){
    quit "UNKNOWN", "couldn't determine user to send to NameNode from environment variables (\$USER, \$USERNAME) or getpwuid() call";
}
vlog_option "user", $user;
vlog2;

my $webhdfs_uri = 'webhdfs/v1';
foreach my $host (@hosts){
    my $ip  = validate_resolvable($host);
    vlog2 "resolved $host to $ip";
}
vlog2;

$path =~ s/^\///;
my $url_main = "$webhdfs_uri/$path?user.name=$user&op="; # uppercase OP= only works on WebHDFS, not on HttpFS

$ua->show_progress(1) if $debug;

my $namenode_index = 0;
# track which namenodes we have tried so we can wrap back around rather than just incrementing $namenode_index which would miss a failover in the direction of index decrease
my @attempted_namenodes = ( $hosts[$namenode_index] );

sub check_response($){
    my $response = shift;
    my $content  = $response->content;
    chomp $content;
    vlog3 "returned HTML:\n\n" . ( $content ? $content : "<blank>" ) . "\n";
    vlog2 "http code: " . $response->code;
    vlog2 "message: " . $response->message . "\n";
    if(!$response->is_success){
        my $err = $response->code . " " . $response->message;
        my $json;
        try {
            $json = decode_json($content);
        };
        if(defined($json->{"RemoteException"}->{"javaClassName"})){
            if($json->{"RemoteException"}->{"javaClassName"} eq "java.io.FileNotFoundException"){
                $err = "";
            } elsif($json->{"RemoteException"}->{"javaClassName"} eq "org.apache.hadoop.ipc.StandbyException" and scalar @attempted_namenodes < scalar @hosts){
                foreach(my $i = 0; $i < scalar @hosts; $i++){
                    unless(grep { $_ eq $hosts[$i] } @attempted_namenodes){
                        $namenode_index = $i;
                        push(@attempted_namenodes, $hosts[$namenode_index]);
                    }
                }
                vlog2 "got Standby NameNode exception, failing over to other NameNode $hosts[$namenode_index]\n";
                return 0;
            } else {
                $err .= ": " . $json->{"RemoteException"}->{"javaClassName"};
            }
        }
        if(defined($json->{"RemoteException"}->{"message"})){
            $err .= ": " if $err;
            $err .= $json->{"RemoteException"}->{"message"};
        }
        quit "CRITICAL", $err;
    }
    return 1;
}

# For prototype checking
sub write_hdfs_file();
sub read_hdfs_file();
sub delete_hdfs_file();
sub get_hdfs_filestatus();

sub write_hdfs_file(){
    # Do not use resolved IP address here, use originally supplied host FQDN otherwise it prevents Kerberos authentication
    # Dynamically increment $namenode_index so we can failover and try the other NameNode
    my $url = "http://$hosts[$namenode_index]:$port/${url_main}CREATE&overwrite=false";
    $timeout_current_action = "writing file" . ( @attempted_namenodes > 1 ? " after failing over to other host" : "");
    vlog2 "writing canary file '$canary_file'";
    vlog3 "PUT $url";
    my $response = $ua->put($url, Content => $canary_contents, "Content-Type" => "application/octet-stream");
    unless(check_response($response)){
        $response = write_hdfs_file();
    }
    return $response;
}

sub read_hdfs_file(){
    # Do not use resolved IP address here, use originally supplied host FQDN otherwise it prevents Kerberos authentication
    # Dynamically increment $namenode_index so we can failover and try the other NameNode
    my $url = "http://$hosts[$namenode_index]:$port/${url_main}OPEN&offset=0&length=1024";
    $timeout_current_action = "reading file" . ( @attempted_namenodes > 1 ? " after failing over to other host" : "");
    vlog3 "GET $url";
    my $response = $ua->get($url);
    unless(check_response($response)){
        $response = read_hdfs_file();
    }
    return $response;
}

sub delete_hdfs_file(){
    # Do not use resolved IP address here, use originally supplied host FQDN otherwise it prevents Kerberos authentication
    # Dynamically increment $namenode_index so we can failover and try the other NameNode
    my $url = "http://$hosts[$namenode_index]:$port/${url_main}DELETE&recursive=false";
    $timeout_current_action = "deleting file" . ( @attempted_namenodes > 1 ? " after failing over to other host" : "");
    vlog3 "DELETE $url";
    my $response = $ua->delete($url);
    unless(check_response($response)){
        $response = delete_hdfs_file();
    }
    return $response;
}

sub get_hdfs_filestatus(){
    # Do not use resolved IP address here, use originally supplied host FQDN otherwise it prevents Kerberos authentication
    # Dynamically increment $namenode_index so we can failover and try the other NameNode
    my $url = "http://$hosts[$namenode_index]:$port/${url_main}GETFILESTATUS";
    $timeout_current_action = "getting " . (lc($file_checks{"type"}) || "path") . " status" . ( @attempted_namenodes > 1 ? " after failing over to other host" : "");
    vlog3 "GET $url";
    my $response = $ua->get($url);
    unless(check_response($response)){
        $response = get_hdfs_filestatus();
    }
    return $response;
}

if($write){
    my $response = write_hdfs_file();
    $msg = "HDFS canary file written";
    vlog2 "reading canary file back";
    $response = read_hdfs_file();
    unless($response->content eq $canary_contents){
        quit "CRITICAL", "mismatch on reading back canary file's contents (expected: '$canary_contents', got: '" . $response->content . "')";
    }
    $msg .= ", contents read back and verified successfully";
    vlog2 "deleting canary file";
    $response = delete_hdfs_file();
} else {
    vlog2 "getting " . (lc($file_checks{"type"}) || "path");
    my $response = get_hdfs_filestatus();
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
        if($file_checks{$_}){
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
