#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-10-05 19:13:20 +0100 (Sat, 05 Oct 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check if a given file is present in AWS S3 via the HTTP Rest API

Bucket names must follow the more restrictive 3 to 63 alphanumeric character international standard, dots are not supported in the bucket name due to using strict DNS shortname regex validation";

$VERSION = "0.4.1";

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
use Time::HiRes 'time';
use XML::Simple;

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

my $aws_host = "s3.amazonaws.com";
my $bucket;
my $file;

my $aws_access_key;
my $aws_secret_key;

my $GET    = 0;
my $no_ssl = 0;
my $ssl_ca_path;
my $ssl_noverify;

%options = (
    "f|file=s"         => [ \$file,             "AWS S3 object path for the file" ],
    "b|bucket=s"       => [ \$bucket,           "AWS S3 bucket" ],
    "aws-access-key=s" => [ \$aws_access_key,   "\$AWS_ACCESS_KEY - can be passed on command line or preferably taken from environment variable" ],
    "aws-secret-key=s" => [ \$aws_secret_key,   "\$AWS_SECRET_KEY - can be passed on command line or preferably taken from environment variable" ],
    "G|get"            => [ \$GET,              "Perform full HTTP GET request instead of default HTTP HEAD. This will download the whole file, useful if you want to see the full download time from AWS S3. You may need to increase the --timeout to fetch file if more than a few MB" ],
    "no-ssl"           => [ \$no_ssl,           "Don't use SSL, connect to AWS S3 with plaintext HTTP instead of HTTPS (not recommended)" ],
    "ssl-CA-path=s"    => [ \$ssl_ca_path,      "Path to CA certificate directory for validating SSL certificate" ],
    "ssl-noverify"     => [ \$ssl_noverify,     "Do not verify SSL certificate from AWS S3 (not recommended)" ],
);
@usage_order = qw/file bucket aws-access-key aws-secret-key get no-ssl ssl-CA-path ssl-noverify/;

if(not defined($aws_access_key) and defined($ENV{"AWS_ACCESS_KEY"})){
    $aws_access_key = $ENV{"AWS_ACCESS_KEY"};
}
if(not defined($aws_secret_key) and defined($ENV{"AWS_SECRET_KEY"})){
    $aws_secret_key = $ENV{"AWS_SECRET_KEY"};
}

get_options();

$aws_host       = validate_host($aws_host);
$file           = validate_filename($file);
$bucket         = validate_aws_bucket($bucket);
$aws_access_key = validate_aws_access_key($aws_access_key);
$aws_secret_key = validate_aws_secret_key($aws_secret_key);

if((defined($ssl_ca_path) or defined($ssl_noverify)) and $no_ssl){
    usage "cannot specify ssl options and --no-ssl at the same time";
}
if(defined($ssl_noverify)){
    $ua->ssl_opts( verify_hostname => 0 );
}
if(defined($ssl_ca_path)){
    $ssl_ca_path = validate_directory($ssl_ca_path, "SSL CA directory", undef, "no vlog");
    $ua->ssl_opts( ssl_ca_path => $ssl_ca_path );
}
if($no_ssl){
    vlog_option "ssl enabled",  "false";
} else {
    vlog_option "ssl enabled",  "true";
    vlog_option "SSL CA Path",  $ssl_ca_path  if defined($ssl_ca_path);
    vlog_option "ssl noverify", "true" if $ssl_noverify;
}

vlog2;
set_timeout();
set_http_timeout($timeout - 1);

$ua->show_progress(1) if $debug;

$status = "OK";

my $host_header = "$bucket.$aws_host";
my $date_header = strftime("%a, %d %b %Y %T %z", gmtime);

$file =~ s/^\///;

my $protocol = "https";
$protocol = "http" if $no_ssl;
my $url = "$protocol://$aws_host/$file";

my $request_type = "HEAD";
$request_type = "GET" if $GET;

# very tricky, had to read the docs to get this
# http://docs.aws.amazon.com/AmazonS3/latest/dev/RESTAuthentication.html
my $canonicalized_string = "$request_type\n\n\n$date_header\n/$bucket/$file";
# converts in place
utf8::encode($canonicalized_string);
#vlog_option "canonicalized_string", "'$canonicalized_string'";

vlog2 "crafting authenticated request";
my $request = HTTP::Request->new($request_type => $url);
$request->header("Host" => $host_header);
$request->header("Date" => $date_header);
my $signature = encode_base64(hmac_sha1($canonicalized_string, $aws_secret_key));
my $authorization_header = "AWS $aws_access_key:$signature";
$request->header("Authorization" => $authorization_header);

validate_resolvable($aws_host);
vlog2 "querying $request_type $url";
my $start_time = time;
my $res = $ua->request($request);
my $end_time = time;
my $time_taken = sprintf("%.2f", $end_time - $start_time);
vlog3 "status line: " . $res->status_line . "\n";
debug "content: " . $res->content . "\n";

if($res->code eq 200){
    if($GET){
        $msg = "retrieved file '$file' from";
    } else {
        $msg = "verified file '$file' exists in";
    }
    $msg .= " $aws_host in $time_taken secs | time_taken=${time_taken}s";
} else {
    critical;
    my $data;
    if($res->content){
        $data = XMLin($res->content, forcearray => 1, keyattr => []);
    }
    $msg = "failed to retrieve file '$file' from $aws_host: " . $res->status_line;
    if(defined($data)){
        $msg .= " - " . $data->{Message}[0];
    }
}

quit $status, $msg;
