#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-08-23 10:57:45 +0100 (Tue, 23 Aug 2011)
#
#  http://github.com/harisekhon
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to test SSH login credentials. Originally written to verify the login credentials across Dell DRAC infrastructure";

$VERSION = "0.9.4";

use strict;
use warnings;
# Using Net::SSH::Expect because Net::SSH requires keys and we're testing user/pass, and Net::SSH::Perl has horrific and broken rpm dependencies
use Net::SSH::Expect;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

$port        = 22;
$timeout_max = 130;
$timeout_min = 10;

%options = (
    "H|host=s"          => [ \$host, "Host to connect to" ],
    "P|port=s"          => [ \$port, "Port to connect to" ],
    "u|user|username=s" => [ \$user, "User to connect with" ],
    "p|pass|password=s" => [ \$password, "Password to connect with" ]
);

get_options();

$host = validate_host($host);
$port = validate_port($port);

defined($user)     || usage "ssh password not defined";
defined($password) || usage "ssh username not defined";
$user     = validate_user($user);
$password = validate_password($password);

vlog2;
set_timeout();

my $login_timeout = int($timeout / 5);
vlog "setting login timeout to $login_timeout secs\n";

vlog "logging in to host '$host' with username '$user', password '$password' (login timeout: $login_timeout secs)";
my $ssh = Net::SSH::Expect->new(
                                host       => $host,
                                user       => $user,
                                password   => $password,
                                # login timeout needs to be at least 4 secs to allow for slow ass Drac controller prompts, which is why I restrict min $timeout to be 10 secs causing min $login_timeout to be 5 secs
                                timeout    => $login_timeout,
                                log_stdout => $verbose,
                                ssh_option => "-p $port"
                                ) or quit "CRITICAL", "failed to connect to host '$host:$port': $!";

# Workaround as the Net::SSH:Expect module errors out with an exit code 5 due to a die call in the module
#my $die_sub = $SIG{__DIE__};
$SIG{__DIE__} = sub {
    my $str = $_[0];
    $str =~ s/ at [\w\.\/_-]+\/$progname line \d+\s*$//;
    $str =~ s/(The ssh process was terminated)./$1 (connection failure)/;
    quit $str;
};
#my $result = $ssh->login(qr/ogin:\s*$/, qr/(?:[Pp]assword.*?|[Pp]assphrase.*?):/, 0);
#my $result = $ssh->login() or quit "CRITICAL", "SSH login failed to connect to host '$host:$port': $!";
#$ssh->close();
#$SIG{__DIE__} = $die_sub;

# alternative way of handling this manually, login() doesn't seem to be handling host key auth right now
#
$ssh->run_ssh() or quit "CRITICAL", "SSH login failed with user '$user'";
vlog "ssh forked\n";
$ssh->waitfor('.*(?::|\?|\n)\s*', $login_timeout, "-re");
my $result = $ssh->match();
$result =~ s/^\r?\n?$//o if $result;
quit "CRITICAL", "timeout after $login_timeout secs waiting for initial prompt" unless $result;
$result =~ /Name or service not known/io and quit "CRITICAL", "DNS lookup failure on '$host'";
$result =~ /Connection refused/io and quit "CRITICAL", "Connection refused to '$host:$port'";
vlog "\n\nchecking for host key prompt";
while($result =~ /The authenticity of host .+ can't be established|key fingerprint is/){
    $ssh->waitfor('.*(?::|\?|\n)\s*', $login_timeout, "-re");
    $result = $ssh->match();
    $result =~ s/^\r?\n?$//o if $result;
}
quit "CRITICAL", "timeout after $login_timeout secs waiting for password/host key prompt" unless $result;
if($result and $result =~ /Are you sure you want to continue connecting \(yes\/no\)\?/smio){
    vlog "host key prompt detected, sending 'yes'";
    $ssh->send("yes");
    vlog "\nattempting to read prompt again (timeout: $login_timeout seconds)\n";
    #$result = $ssh->read_all($login_timeout);
    $ssh->waitfor('(?:[Pp]assword|[Pp]assphrase).*:\s', $login_timeout, "-re");
    $result = $ssh->match();
    $result =~ s/^\r?\n?$//o if $result;
    quit "CRITICAL", "password prompt not returned within $login_timeout seconds" unless $result;
}
vlog "\n\nchecking for password prompt";
if($result){
    if($result =~ /(?:password|passphrase).*:/io){
        vlog "caught password prompt, sending password '$password'";
        $ssh->send($password);
        vlog "\nreading password response (timeout: $login_timeout seconds)\n";
        $ssh->waitfor('.*?[>$#:]', $login_timeout, "-re");
        $result = $ssh->match();
        $result =~ s/\r?\n?// if $result;
        quit "CRITICAL", "password prompt response not received within $login_timeout seconds" unless $result;
    } else {
        quit "CRITICAL", "password prompt was not found in the output from host '$host:$port' (output was '$result')";
    }
} else {
}
$result =~ s/\s*$//;

#vlog "";
$result =~ s/^\s*\n//mo;
$result =~ s/^Last login.+\n//mio;
vlog "\n\nprompt: '$result'";

if($result =~ /(?:password|passphrase).*:/io){
    vlog "password prompt has been re-displayed, username/password combination has failed";
    quit "CRITICAL", "SSH login failed with user '$user'";
} elsif($result =~ /[>#~]/o){
    quit "OK", "SSH login successful with user '$user' (prompt returned: '$result')";
} else {
    quit "CRITICAL", "SSH login failed with user '$user' (unconfirmed prompt: '$result')";
}

quit "UNKNOWN", "hit end of plugin";
