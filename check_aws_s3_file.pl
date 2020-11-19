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
$DESCRIPTION = "Nagios Plugin to check an S3 file exists via the AWS S3 API for any S3 compatible storage

Useful for checking:

1. latest ETL files are available
2. job status files like _SUCCESS
3. internal private cloud storage is online and known data is accessible
4. files are being updated often

Bucket names must follow the more restrictive 3 to 63 alphanumeric character international standard, dots are not supported in the bucket name due to using strict DNS shortname regex validation

./check_aws_s3_file.pl --bucket bucket1 --file data-\$(date '+%Y-%m-%d')

Tested on AWS S3 and Minio (open source private cloud S3 storage)
";

$VERSION = "0.6.2";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Digest::SHA qw(sha256_hex hmac_sha256 hmac_sha256_hex);
use LWP::UserAgent;
use MIME::Base64;
use POSIX 'strftime';
use Time::HiRes 'time';
use XML::Simple;

our $ua = LWP::UserAgent->new;
$ua->agent("Hari Sekhon $progname version $main::VERSION");

env_creds('AWS');

set_host_default("s3.amazonaws.com");
set_port_default(443);
my $bucket;
my $file;

my $aws_access_key;
my $aws_secret_key;

my $GET    = 0;
my $no_ssl = 0;
my $ssl_ca_path;
my $ssl_noverify;
my $region;
my $age;
my $size;

%options = (
    %hostoptions,
    "r|region=s"       => [ \$region,           "AWS Region, i.e. us-east-1" ],
    "b|bucket=s"       => [ \$bucket,           "AWS S3 bucket" ],
    "f|file=s"         => [ \$file,             "AWS S3 file path" ],
    "aws-access-key=s" => [ \$aws_access_key,   "AWS Access Key (\$AWS_ACCESS_KEY)" ],
    "aws-secret-key=s" => [ \$aws_secret_key,   "AWS Secret Key (\$AWS_SECRET_KEY)" ],
    "G|get"            => [ \$GET,              "Perform full HTTP GET request instead of default HTTP HEAD. This will download the whole file, useful if you want to see the full download time from AWS S3. You may need to increase the --timeout to fetch file if more than a few MB" ],
    "no-ssl"           => [ \$no_ssl,           "Don't use SSL, connect to AWS S3 with plaintext HTTP instead of HTTPS (not recommended unless you're using a private cloud storage like Minio)" ],
    "ssl-CA-path=s"    => [ \$ssl_ca_path,      "Path to CA certificate directory for validating SSL certificate" ],
    "ssl-noverify"     => [ \$ssl_noverify,     "Do not verify SSL certificate from AWS S3 (not recommended)" ],
    "age=s"            => [ \$age,              "Maximum duration in seconds since the last-modified for the file to be deemed as valid" ],
    "size=s"           => [ \$size,             "Minimum size in bytes for the file to be deemed as valid" ],
);
@usage_order = qw/host port bucket file aws-access-key aws-secret-key get no-ssl ssl-CA-path ssl-noverify region age/;

if(not defined($aws_access_key) and defined($ENV{"AWS_ACCESS_KEY"})){
    $aws_access_key = $ENV{"AWS_ACCESS_KEY"};
}
if(not defined($aws_secret_key) and defined($ENV{"AWS_SECRET_KEY"})){
    $aws_secret_key = $ENV{"AWS_SECRET_KEY"};
}

get_options();

$host           = validate_host($host);
$port           = validate_port($port);
$file           = validate_filename($file);
$bucket         = validate_aws_bucket($bucket);
$region         = validate_chars($region, 'aws region', 'A-Za-z0-9-');
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

my @now = gmtime;
my $host_header = "$bucket.$host";
my $date_header = strftime("%a, %d %b %Y %T %z", @now);

$file =~ s/^\///;

my $protocol = "https";
$protocol = "http" if $no_ssl;
my $url = "$protocol://$bucket.$host/$file";

my $request_type = "HEAD";
$request_type = "GET" if $GET;

my $isodate = strftime("%Y%m%dT%H%M%SZ", @now);
my $isoday = strftime("%Y%m%d", @now);

my $content_hash = sha256_hex("");
my $signed_headers = "host;x-amz-content-sha256;x-amz-date";
my $canonical_request = "$request_type\n/$file\n\nhost:$host_header\nx-amz-content-sha256:$content_hash\nx-amz-date:$isodate\n\n$signed_headers\n$content_hash";

my $hash_of_canonicals = sha256_hex($canonical_request);

my $string_to_sign = "AWS4-HMAC-SHA256\n$isodate\n$isoday/$region/s3/aws4_request\n$hash_of_canonicals";

my $kDate = hmac_sha256($isoday,"AWS4" . $aws_secret_key);
my $kRegion = hmac_sha256($region,$kDate);
my $kService = hmac_sha256("s3",$kRegion);
my $signing_key = hmac_sha256("aws4_request",$kService);

my $signature = hmac_sha256_hex($string_to_sign, $signing_key);
my $credential = "$aws_access_key/$isoday/$region/s3/aws4_request";

my $authorization_header = "AWS4-HMAC-SHA256 Credential=$credential, SignedHeaders=$signed_headers, Signature=$signature";

vlog3 "authorization_header: '$authorization_header'";
vlog2 "crafting authenticated request";

my $request = HTTP::Request->new($request_type => $url);
$request->header("Host" => $host_header);
$request->header("Date" => $date_header);
$request->header("Authorization" => $authorization_header);
$request->header("X-Amz-Content-SHA256" => $content_hash);
$request->header("X-Amz-Date" => $isodate);

validate_resolvable($host);
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
    $msg .= " $host";

    my $age_secs = int(time - $res->last_modified);
    if($age and $age_secs > $age){
        critical;
        $msg .= " but it is too old ($age_secs > $age secs)";
    }
    if($size && $res->content_length < $size){
        critical;
        $msg .= " but is too small : " . ($res->content_length);
    }
    $msg .= " | query_time=${time_taken}s";
} else {
    critical;
    my $data;
    if($res->content){
        $data = XMLin($res->content, forcearray => 1, keyattr => []);
    }
    $msg = "failed to retrieve file '$file' from $host: " . $res->status_line;
    if(defined($data)){
        $msg .= " - " . $data->{Message}[0];
    }
}

quit $status, $msg;
