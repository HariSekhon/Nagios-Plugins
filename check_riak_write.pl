#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-07-21 03:06:42 +0100 (Sun, 21 Jul 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#  

$DESCRIPTION = "Nagios Plugin to check Riak is working by writing + reading back a new uniq key/value via HTTP Rest API on a given node";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use LWP::UserAgent;
use Time::HiRes 'time';

my $ua = LWP::UserAgent->new;
my $header = "Hari Sekhon $progname version $main::VERSION";
$ua->agent($header);

my $default_port = 8098;
$port = $default_port;

%options = (
    "H|host=s"         => [ \$host,         "Riak node to connect to" ],
    "P|port=s"         => [ \$port,         "Port to connect to (defaults to $default_port)" ],
    "w|warning=s"      => [ \$warning,      "Warning  threshold in seconds for each read/write/delete operation" ],
    "c|critical=s"     => [ \$critical,     "Critical threshold in seconds for each read/write/delete operation" ],
);

@usage_order = qw/host port warning critical/;
get_options();

$host      = validate_hostname($host);
$port      = validate_port($port);
my $node   = "riak node '$host:$port'";
my $epoch  = time;
my $bucket = "nagios";
my $key    = "$host-$epoch";
my $bucket_key = "key '$key' bucket '$bucket'";
my @chars = ("A".."Z", "a".."z", 0..9);
my $value  = "";
$value    .= $chars[rand @chars] for 1..12;
my $url    = "http://$host:$port/riak/$bucket/$key";
vlog_options "bucket", $bucket;
vlog_options "key",    $key;
vlog_options "value",  $value;
vlog_options "url",    $url;
validate_thresholds(undef, undef, { "simple" => "upper", "positive" => 1, "integer" => 0 } );

$ua->show_progress(1) if $debug;

vlog2;
set_timeout();

sub riak_key($){
    my $action = $_[0];
    my $node_action;
    my $req;
    if($action eq "write"){
        $req = HTTP::Request->new('PUT', $url, [ "Content-Type" => "text/plain", "X-Riak-Meta-Nagios" => $header ], $value);
        vlog2 "writing $bucket_key on $node";
        $node_action = "write to $node";
    } elsif($action eq "read"){
        $req = HTTP::Request->new('GET', $url);
        vlog2 "reading $bucket_key from $node";
        $node_action = "read from $node";
    } elsif($action eq "delete"){
        $req = HTTP::Request->new('DELETE', $url);
        vlog2 "deleting $bucket_key from $node";
        $node_action = "delete from $node";
    } else {
        code_error "invalid action passed to riak_key()";
    }
    my $start_time  = time;
    my $response    = $ua->request($req);
    my $end_time    = time;
    my $time_taken  = sprintf("%.4f", $end_time - $start_time);
    my $status_line = $response->status_line;
    my $content     = $response->content;
    chomp $content;
    vlog2 "status:  $status_line";
    vlog3 "body:    $content\n";
    if($action eq "write"){
        # Docs say it should return 201 Created but really it returns 204 No Content, at least in latest 1.4 release
        if(($response->code eq 201 and $response->message eq "Created") or ($response->code eq 204 and $response->message eq "No Content")){
            $msg .= ", wrote key in $time_taken secs";
        } else {
            quit "CRITICAL", "failed to $node_action after $time_taken secs: $status_line"
        }
    } elsif($action eq "read"){
        if($response->code eq 200 and $response->message eq "OK"){
            $msg .= ", read key in $time_taken secs";
        } elsif($response->code eq 300 or $response->code eq "Multiple Choices"){
            warning;
            $msg .= ", MULTIPLE key read choices returned in $time_taken secs, ";
        } else {
            quit "CRITICAL", "failed to $node_action after $time_taken secs: $status_line";
        }
        vlog2 "\nchecking key value content is '$value'";
        if($content ne $value){
            quit "CRITICAL", "value mismatch on read back of written $bucket_key on $node! Wrote '$value', but '$content' returned by same node!";
        }
    } elsif($action eq "delete"){
        if($response->code eq 204 and $response->message eq "No Content"){
            $msg .= ", deleted key in $time_taken secs";
        } else {
            quit "CRITICAL", "failed to $node_action after $time_taken secs: $status_line";
        }
    } else {
        code_error "invalid action passed to riak_key()";
    }
    vlog2;
    return $time_taken;
}

$status = "OK";

my $msg_perf = " | ";
my $msg_thresholds = "s;" . ($thresholds{"warning"}{"upper"} ? $thresholds{"warning"}{"upper"} : "") . ";" . ($thresholds{"critical"}{"upper"} ? $thresholds{"critical"}{"upper"} : "") . ";0;";
my $write_time  = riak_key("write");
my $read_time   = riak_key("read");
my $delete_time = riak_key("delete");
$msg_perf .= " write_time=${write_time}${msg_thresholds}";
$msg_perf .= " read_time=${read_time}${msg_thresholds}";
$msg_perf .= " delete_time=${delete_time}${msg_thresholds}";
$msg =~ s/^,\s*//;
$msg .= " from $node";
check_thresholds($delete_time, 1);
check_thresholds($read_time, 1);
check_thresholds($write_time);
$msg .= $msg_perf;

quit "$status", "$msg";
