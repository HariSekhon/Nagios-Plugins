#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-05 19:13:20 +0100 (Sat, 05 Oct 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

# TODO: add SSL support similar to the Cloudera Manager plugin

$DESCRIPTION = "Nagios Plugin to check if a given file is present in AWS S3 via the HTTP Rest API

Bucket names must follow the more restrictive 3 to 63 alphanumeric character international standard, dots are not supported in the bucket name due to using strict DNS shortname regex validation";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Digest::SHA 'hmac_sha1';
use LWP::UserAgent;
use MIME::Base64;
use POSIX 'strftime';
use XML::Simple;

my $aws_host = "s3.amazonaws.com";
my $bucket;
my $file;

my $aws_access_key;
my $aws_secret_key;

%options = (
    "f|file=s"         => [ \$file,           "AWS S3 object path for the file" ],
    "b|bucket=s"       => [ \$bucket,         "AWS S3 bucket" ],
    "aws-access-key=s" => [ \$aws_access_key, "\$AWS_ACCESS_KEY - can be passed on command line or preferably taken from environment variable" ],
    "aws-secret-key=s" => [ \$aws_secret_key, "\$AWS_SECRET_KEY - can be passed on command line or preferably taken from environment variable" ],
);

@usage_order = qw/file bucket aws-access-key aws-secret-key/;
get_options();

if(not defined($aws_access_key) and defined($ENV{"AWS_ACCESS_KEY"})){
    $aws_access_key = $ENV{"AWS_ACCESS_KEY"};
    vlog2 "read AWS_ACCESS_KEY from environment: $aws_access_key";
}
if(not defined($aws_secret_key) and defined($ENV{"AWS_SECRET_KEY"})){
    $aws_secret_key = $ENV{"AWS_SECRET_KEY"};
    vlog2 "read AWS_SECRET_KEY from environment: $aws_secret_key";
}
vlog2;

$aws_host       = validate_host($aws_host);
$file           = validate_filename($file);
$bucket         = validate_aws_bucket($bucket);
$aws_access_key = validate_aws_access_key($aws_access_key);
$aws_secret_key = validate_aws_secret_key($aws_secret_key);

vlog2;
set_timeout();

$status = "OK";

my $host_header = "$bucket.$aws_host";
my $date_header = strftime("%a, %d %b %Y %T %z", gmtime);

$file =~ s/^\///;

my $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname $main::VERSION");
$ua->timeout($timeout - 2);
$ua->show_progress(1) if $debug;

# very tricky, had to read the docs to get this
# http://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html
my $canonicalized_string = "HEAD\n\n\n$date_header\n/$bucket/$file";
# converts in place
utf8::encode($canonicalized_string);
#vlog_options "canonicalized_string", "'$canonicalized_string'";

validate_resolveable($aws_host);
my $request = HTTP::Request->new(HEAD => "http://$aws_host/$file");
$request->header("Host" => $host_header);
$request->header("Date" => $date_header);
my $signature = encode_base64(hmac_sha1($canonicalized_string, $aws_secret_key));
my $authorization_header = "AWS $aws_access_key:$signature";
$request->header("Authorization" => $authorization_header);
my $res = $ua->request($request);
vlog3 "status line: " . $res->status_line . "\ncontent: " . $res->content . "\n";

if($res->code eq 200){
    $msg = "retrieved file '$file' from $aws_host";
} else {
    critical;
    my $data = XMLin($res->content, forcearray => 1, keyattr => []);
    $msg = "failed to retrieve file '$file' from $aws_host: " . $res->status_line . " - " . $data->{Message}[0];
}

quit $status, $msg;
