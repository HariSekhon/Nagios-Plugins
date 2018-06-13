#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-24 18:28:09 +0100 (Wed, 24 Jul 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a disk is writable and functioning properly by writing a tiny canary file with unique generated contents and then reading it back to make sure it was written properly.

Useful to detect I/O errors and disks that have been re-mounted read-only as often happens when I/O errors in the disk subsystem are detected by the kernel

See also check_linux_disk_mounts_read_only.py

Tested on various Linux distributions (CentOS / RHEL 5+, Debian, Ubuntu, Alpine) and Mac OS X for several years";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use File::Spec;
use File::Temp;

my $dir;

%options = (
    "d|directory=s"   =>  [ \$dir,    "Directory to write the canary file to. Set this to a directory on the mount point of the disk you want to check" ],
);

get_options();

defined($dir) or usage "directory not specified";
$dir = File::Spec->rel2abs($dir); # also canonicalizes, but sets "." if $dir undefined
$dir = validate_directory($dir);
my $random_string = sprintf("%s %s %s", $progname, time, random_alnum(20));
vlog_option "random string", "'$random_string'\n";

set_timeout();

$status = "OK";

my $fh;
vlog2 "creating canary file";
try {
    $fh = File::Temp->new(TEMPLATE => "$dir/${progname}_XXXXXXXXXX");
};
catch_quit "failed to create canary file in $dir";
my $filename = $fh->filename;
vlog2 "canary file created: '$filename'\n";

vlog2 "writing random string to canary file";
try {
    print $fh $random_string;
};
catch_quit "failed to write random string to canary file '$filename'";
vlog2 "wrote canary file\n";

vlog3 "seeking to beginning of canary file";
try {
    seek($fh, 0, 0) or quit "CRITICAL", "failed to seek to beginning of canary file '$filename': $!";
};
catch_quit "failed to seek to beginning of canary file '$filename'";
vlog3 "seeked back to start of canary file\n";

my $contents = "";
my $bytes;

vlog2 "reading contents of canary file back";
try {
    $bytes = read($fh, $contents, 100);
};
catch_quit "failed to read back from canary file '$filename'";
vlog2 "$bytes bytes read back from canary file\n";
vlog3 "contents = '$contents'\n";

vlog3 "comparing random string written to contents of canary file";
if($contents eq $random_string){
    vlog2 "random string written and contents read back match OK\n";
} else {
    quit "CRITICAL", "canary file I/O error in $dir (written => read contents differ: '$random_string' vs '$contents')";
}

$msg = "canary file I/O written => read back $bytes bytes successfully in $dir, unique contents verified";

quit $status, $msg;
