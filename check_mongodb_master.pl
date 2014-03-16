#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2013-12-17 22:35:14 +0000 (Tue, 17 Dec 2013)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a given Mongod is the Master of a Replica Set";

$VERSION = "0.1";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Data::Dumper;
use MongoDB::MongoClient;

set_port_default(27017);

env_creds("MongoDB");

my $ssl               = 0;
my $sasl              = 0;
my $sasl_mechanism    = "GSSAPI";

%options = (
    %hostoptions,
    %useroptions,
    "ssl"              => [ \$ssl,           "Enable SSL, MongDB libraries must have been compiled with SSL and server must support it. Experimental" ],
    "sasl"             => [ \$sasl,          "Enable SASL authentication, must be compiled in to the MongoDB perl driver to work. Experimental" ],
    "sasl-mechanism=s" => [ \$sasl_mechanism, "SASL mechanism (default: GSSAPI eg Kerberos on MongoDB Enterprise 2.4+ in which case this should be run from a valid kinit session, alternative PLAIN for LDAP using user/password against MongoDB Enterprise 2.6+ which is sent in plaintext so should be used over SSL). Experimental" ],
);

@usage_order = qw/host port database collection user password write-concern read-concern wtimeout ssl sasl sasl-mechanism warning critical precision/;
get_options();

$host       = validate_host($host);
$port       = validate_port($port);
$user       = validate_user($user);
$password   = validate_password($password) if $password;
grep { $sasl_mechanism eq $_ } qw/GSSAPI PLAIN/ or usage "invalid sasl-mechanism specified, must be either GSSAPI or PLAIN";
vlog_options "ssl",  "enabled" if $ssl;
vlog_options "sasl", "enabled" if $sasl;
vlog_options "sasl-mechanism", $sasl_mechanism if $sasl;

vlog2;
set_timeout();

$status = "OK";

my $ip = validate_resolvable($host);
vlog2 "resolved '$host' to '$ip'";

my $client;
try {
    $client = MongoDB::MongoClient->new(
                                        "host"           => "$host:$port",
                                        # hangs when giving only nodes of a replica set that aren't the Primary
                                        #"find_master"    => 1,
                                        "timeout"        => int($timeout * 1000 / 4), # connection timeout
                                        #"wtimeout"       => $wtimeout,
                                        "query_timeout"  => int($timeout * 1000 / 4),
                                        "ssl"            => $ssl,
                                        "sasl"           => $sasl,
                                        "sasl-mechanism" => $sasl_mechanism,
                                       ) || quit "CRITICAL", "$!";
};
catch_quit "failed to connect to MongoDB host '$host:$port' ($ip)";

vlog2 "connection initiated to $host:$port\n";

my @dbs = $client->database_names;
@dbs or quit "UNKNOWN", "no databases found on Mongod server, cannot call ismaster";
my $database = $dbs[0];
my $db;
try {
    $db = $client->get_database($database)   || quit "CRITICAL", "failed to select database '$database': $!";
};
catch_quit "failed to select database '$database'";

vlog2 "selected first database '$database'";

my $ismaster = $db->run_command({"ismaster" => 1});

vlog3(Dumper($ismaster));

defined($ismaster->{"primary"}) or quit "UNKNOWN", "failed to find 'primary' - not part of a Replica Set?";
defined($ismaster->{"me"})      or quit "UNKNOWN", "failed to find 'me' field in ismaster output. API may have changed. $nagios_plugins_support_msg";

vlog2 "got master\n";

my $master = $ismaster->{"primary"};
my $me     = $ismaster->{"me"};

$msg = "master is '$master'";

if($master ne $me){
    critical;
    $msg .= " (this host is '$me')";
}

quit $status, $msg;
