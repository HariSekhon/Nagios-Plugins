#!/usr/bin/perl -T
# nagios: -epn
# vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2015-10-25 11:04:34 +0000 (Sun, 25 Oct 2015)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback to help improve or steer this or other code I publish
#
#  http://www.linkedin.com/in/harisekhon
#

$DESCRIPTION = "Nagios Plugin to check a file's checksum against an expected value

Useful if you want to check a file has been deployed and is the same version as stored in say Git

Consider combining with check_git_checkout_branch.pl to ensure you're checking the right file from the right Git branch to check against the deployed version

--verbose mode shows which algorithm has been used in the output";


$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Digest::Adler32;
use Digest::CRC;
use Digest::MD5;
use Digest::SHA;
use Digest::SHA1;

my $file;
my $expected_checksum;
my $algo;
my @valid_algos = qw/sha1 md5 crc adler32 sha256 sha512/;
my $no_compare;

%options = (
    "f|file=s"            =>  [ \$file,               "File to check" ],
    "c|checksum=s"        =>  [ \$expected_checksum,  "Checksum value to expect" ],
    "a|algo|algorithm=s"  =>  [ \$algo,               "Checksum algorithm (@valid_algos. Default: sha1)" ],
    "n|no-compare"        =>  [ \$no_compare,         "Do not expect a checksum or compare to it (otherwise raises unknown if an expected checksum is not given)" ],
);
splice @usage_order, 6, 0, qw/file checksum algorithm no-compare/;

if($progname =~ /sha1/){
    $algo = "sha1";
} elsif($progname =~ /sha256/){
    $algo = "sha256";
} elsif($progname =~ /sha512/){
    $algo = "sha512";
} elsif($progname =~ /md5/){
    $algo = "md5";
} elsif($progname =~ /crc/){
    $algo = "crc";
} elsif($progname =~ /adler32/){
    $algo = "adler32";
}

if($algo){
    delete $options{"a|algo|algorithm=s"};
} else {
    $algo = "sha1";
}

get_options();

$file = validate_filename($file);
$algo = lc $algo;
unless(grep { $algo eq $_ } @valid_algos){
    usage "invalid --algorithm given, must be one of: @valid_algos";
}
vlog_option "algorithm", $algo;
if(defined($expected_checksum)){
    isHex($expected_checksum) or usage "invalid --checksum given, not hexadecimal";
    $no_compare and usage "cannot specify --no-compare and --checksum at the same time";
    vlog_option "expected checksum", $expected_checksum;
}
vlog_option_bool "no-compare", $no_compare;

vlog2;
set_timeout();

$status = "OK";

# validated inside lib
my $fh = open_file($file);
vlog2;

my $digest;

if($algo eq "sha1"){
    $digest = Digest::SHA1->new();
} elsif($algo eq "sha256"){
    $digest = Digest::SHA->new("SHA-256");
} elsif($algo eq "sha512"){
    $digest = Digest::SHA->new("SHA-512");
} elsif($algo eq "md5"){
    $digest = Digest::MD5->new();
} elsif($algo eq "adler32"){
    $digest = Digest::Adler32->new();
} elsif($algo eq "crc"){
    $digest = Digest::CRC->new();
} else {
    quit "UNKNOWN", "unrecognized algorithm";
}

defined($digest) or quit "UNKNOWN", "unable to instantiate digest algorithm '$algo'";

$digest->addfile($fh) or quit "UNKNOWN", "error adding file to be checksummed";

my $checksum = $digest->hexdigest;
defined($checksum) or quit "UNKNOWN", "failed to calculate checksum for file '$file'";

$msg = "file '$file'";
if($verbose){
    $msg .= " algo '$algo'";
}
$msg .= " checksum = '$checksum'";
if(defined($expected_checksum)){
    unless($checksum eq $expected_checksum){
        critical;
        $msg .= " (expected '$expected_checksum')";
    }
} elsif($no_compare){
    # pass
} else {
    unknown;
    $msg .= " (no expected --checksum specified by user to validate against and --no-compare wasn't specified)";
}

quit $status, $msg;
