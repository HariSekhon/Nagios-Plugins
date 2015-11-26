#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-08-23 10:57:45 +0100 (Tue, 23 Aug 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to test SSH login credentials

Originally written for Dell DRAC controllers to verify the login credentials were set properly across the infrastructure

Updated for HP iLO controllers for the same reason, people tend to forget and leave them with default credentials!

Also tested on Linux servers and Mac OS X. May need tweaks for other platforms, or where custom shell prompts are used

Since Dracs and iLOs are very slow, you will need to increase the --timeout for those to something like 50-60 seconds to allow 10-12 secs for each password prompt / response as it auto-calculates it to be 1/5th of global --timeout";

$VERSION = "0.9.6";

use strict;
use warnings;
# Using Net::SSH::Expect because Net::SSH requires keys and we're testing user/pass, and Net::SSH::Perl has horrific and broken rpm dependencies
use Net::SSH::Expect;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;

# regex to expect for successful logins
# no space at end, disparate ssh login prompts don't always have \s$
# these are non-greedy matches, the .* doesn't do anything
my $shell_prompt = '.*[>$#]';
my $login_prompt = '.*[:\?]';

$port        = 22;
$timeout_max = 130;
$timeout_min = 10;

env_creds("SSH");

%options = (
    %hostoptions,
    %useroptions,
);
@usage_order = qw/host port user password/;

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
vlog2 "setting login timeout to $login_timeout secs\n";

vlog2 "logging in to host '$host' with username '$user', password '<omitted>' (login timeout: $login_timeout secs)";
my $ssh = Net::SSH::Expect->new(
                                host       => $host,
                                user       => $user,
                                password   => $password,
                                # login timeout needs to be at least 4 secs to allow for slow ass Drac controller prompts, which is why I restrict min $timeout to be 10 secs causing min $login_timeout to be 5 secs
                                timeout    => $login_timeout,
                                log_stdout => ($verbose > 1 ? $verbose : 0 ),
                                ssh_option => "-p $port -oPreferredAuthentications=keyboard-interactive,password"
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
vlog2 "ssh forked\n";
# doesn't prioritize for \n, nor does it capture .* after :
#$ssh->waitfor('(?:.+\n|[^\n]+\?|[^\n\?]+:).*', $login_timeout, "-re");
$ssh->waitfor($login_prompt, $login_timeout, "-re");
my $result = $ssh->match();
$result =~ s/^\r?\n?$// if $result;
quit "CRITICAL", "timeout after $login_timeout secs waiting for initial prompt" unless $result;
$result =~ /Name or service not known/i and quit "CRITICAL", "DNS lookup failure on '$host'";
$result =~ /Connection refused/i and quit "CRITICAL", "Connection refused to '$host:$port'";
vlog2 "\n\nchecking for host key prompt";
while($result =~ /The authenticity of host .+ can't be established|key fingerprint is/){
    $ssh->waitfor($login_prompt, $login_timeout, "-re");
    $result = $ssh->match();
    $result =~ s/^\r?\n?$// if $result;
}
quit "CRITICAL", "timeout after $login_timeout secs waiting for password/host key prompt" unless $result;
if($result and $result =~ /Are you sure you want to continue connecting \(yes\/no\)\?/smi){
    vlog2 "host key prompt detected, sending 'yes'";
    $ssh->send("yes");
    vlog2 "\nattempting to read prompt again (timeout: $login_timeout seconds)\n";
    #$result = $ssh->read_all($login_timeout);
    $ssh->waitfor('(?:[Pp]assword|[Pp]assphrase).*:\s', $login_timeout, "-re");
    $result = $ssh->match();
    $result =~ s/^\r?\n?$// if $result;
    quit "CRITICAL", "password prompt not returned within $login_timeout seconds after accepting ssh host key" unless $result;
}
vlog2 "\n\nchecking for password prompt";
if($result){
    if($result =~ /(?:password|passphrase).*:/i){
        vlog2 "caught password prompt, sending password";
        $ssh->send($password);
        vlog2 "\nreading password response (timeout: $login_timeout seconds)\n";
        $ssh->waitfor($login_prompt, $login_timeout, "-re");
        $result = $ssh->match();
        $result =~ s/\r?\n?// if $result;
        quit "CRITICAL", "password prompt response not received within $login_timeout seconds" unless $result;
    } else {
        quit "CRITICAL", "password prompt was not found in the output from host '$host:$port' (output was '$result')";
    }
} else {
}
$result =~ s/\s*$//;

#vlog3 "result:\n\n$result";
$result =~ s/^\s*\n//m;
if($result =~ /^Last\s+login.+?$/i){
    $ssh->waitfor($shell_prompt, $login_timeout, "-re");
    $result = $ssh->match();
    defined($result) or quit "UNKNOWN", "shell prompt not received within $login_timeout secs after Last login header";
}
if($result =~ /(?:Mon|Tue|Wed|Thu|Fri|Sat|Sun).*$/i){
    $ssh->waitfor($shell_prompt, $login_timeout, "-re");
    $result = $ssh->match();
    defined($result) or quit "UNKNOWN", "shell prompt not received with $login_timeout secs after Last login date header";
}

if($result =~ /logged[\s-]in/i){
    $ssh->waitfor($shell_prompt, $login_timeout, "-re");
    $result = $ssh->match();
    defined($result) or quit "UNKNOWN", "shell prompt not received within $login_timeout secs after logged in header";
}

# added for HP iLO
if($result =~ /^User:/){
    $ssh->waitfor($shell_prompt);
    $result = $ssh->match();
    defined($result) or quit "UNKNOWN", "shell prompt not received with $login_timeout secs after User: response";
    if($result =~ /$user logged-in to/i){
        vlog2 "HP user logged-in header detected";
        $ssh->waitfor($shell_prompt, $login_timeout, "-re");
        $result = $ssh->match();
        defined($result) or quit "UNKNOWN", "shell prompt not received within $login_timeout secs after 'User:' response";
    }
}

#vlog3 "\n\nprompt: '$result'";

vlog2 "\n";
if($result =~ /(?:password|passphrase).*:/i){
    vlog2 "password prompt has been re-displayed, username/password combination has failed";
    quit "CRITICAL", "SSH login failed with user '$user'";
} elsif($result =~ /$shell_prompt/){
    quit "OK", "SSH login successful with user '$user' (prompt returned: '$result')";
} else {
    quit "CRITICAL", "SSH login failed with user '$user' (unconfirmed prompt: '$result')";
}

quit "UNKNOWN", "hit end of plugin";
