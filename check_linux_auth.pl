#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2011-09-14 14:13:42 +0100 (Wed, 14 Sep 2011)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check authentication mechanisms are working by validating:

- certain users/groups are present
- there are no duplicate UID/GIDs
- groups.allow contains the expected groups and no others

Useful for checking that AD integrated Linux servers are still able to authenticate AD users

See also adjacent check_file_checksum.pl for checking pam.d system-auth has the expected checksum of contents (ie. is configured as expected)
";

$VERSION = "0.8.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
#Getopt::Long::Configure ("no_bundling");

$status = "OK";

my @users;
my @groups;
my $groups_file;
my @groups_allowed;

%options = (
    "u|users=s"         => [ \@users,           "Users to check are present  (prefixing with - ensures they are not present)" ],
    "g|groups=s"        => [ \@groups,          "Groups to check are present (prefixing with - ensures they are not present)" ],
    "groups-file=s"     => [ \$groups_file,     "Group file to check. Expects a file in the format of pam_listfile" ],
    "groups-allowed=s"  => [ \@groups_allowed,  "Groups to expect in the groups.allow file. Alerts critical if the groups present do not match this comma separated list precisely" ]
);

get_options();

@users or usage("must specify at least one user account to check");
@users  = split(",", $users[0])  if $users[0] =~ ",";
@groups = split(",", $groups[0]) if(@groups and $groups[0] =~ ",");
@groups_allowed = split(",", $groups_allowed[0]) if(@groups_allowed and $groups_allowed[0] =~ ",");
#@groups_allowed = split(",", $groups_allowed[0]);
foreach(@users){
    $_ =~ /^([\w]+)$/ or usage("invalid user '$_' given");
    $_ = $1;
}
foreach(@groups){
    $_ =~ /^([\w]+)$/ or usage("invalid group '$_' given");
    $_ = $1;
}
( @groups_allowed and not defined($groups_file) ) and usage("must set both groups-file and groups-allowed if trying to check authorized groups");
if($groups_file and @groups_allowed){
    $groups_file = validate_filename($groups_file);
}

linux_only();
set_timeout();

sub getent {
    my $db = $_[0];
    my $target;
    $target = $_[1] if $_[1];
    ($db eq "passwd" or $db eq "group") or quit "UNKNOWN", "invalid arg passwd to getent function '$db'";
    my %regex;
    $regex{"passwd"} = '^[^:]+:[*x]:\d+:\d+(?::[^:]*){3}$';
    $regex{"group"}  = '^[^:]+:[*x]:\d+:[^:]*$';
    my @output;
    if($target){
        if($db eq "passwd"){
            vlog2("fetching user $target");
        } elsif($db eq "group") {
            vlog2("fetching group $target");
        } else {
            quit("UNKNOWN", "Warning: unrecognized call '$db' to getent function for target '$target'");
        }
        @output = cmd("getent $db $target");
        #vlog("Warning: " . scalar(@output) . " lines returned from getent $db $target (line was '$_')") if(scalar(@output) != 1);
        $output[0] or return 0;
        $output[0] =~ /$regex{$db}/ or quit "CRITICAL", "Unrecognized output format returned by getent $db $target ('$output[0]')";
        $output[0] =~ /^$target:/ or return 0;
    } else {
        if($db eq "passwd"){
            vlog2("fetching users");
        } elsif($db eq "group") {
            vlog2("fetching groups");
        } else {
            quit("UNKNOWN", "Warning: unrecognized call '$db' to getent function");
        }
        @output = cmd("getent $db");
        foreach(@output){
            $_ =~ /$regex{$db}/ or quit "CRITICAL", "Unrecognized output format returned by getent $db ('$_')";
        }
    }
    return @output;
}

my @getent_passwd  = getent("passwd") or quit("CRITICAL", "failed to fetch all users");
my @users_present  = @getent_passwd;
vlog2("fetching groups");
my @getent_group   = cmd("getent group") or quit("CRITICAL", "failed to fetch all groups");
my @groups_present = @getent_group;

##############################
# Check for duplicate UID/GIDs
my %uid;
my %gid;
vlog2("checking for duplicate UIDs");
foreach(@getent_passwd){
    @_ = split(":", $_);
    push(@{$uid{$_[2]}}, $_[0]);
}
foreach(sort keys %uid){
    if(scalar(@{$uid{$_}}) > 1){
        $msg .= scalar(@{$uid{$_}}) . " users with UID '$_' found: " . join(",", sort @{$uid{$_}}) . ". ";
        quit "CRITICAL", $msg;
    }
}
vlog2("checking for duplicate GIDs");
foreach(@getent_group){
    @_ = split(":", $_);
    push(@{$gid{$_[2]}}, $_[0]);
}
foreach(sort keys %gid){
    if(scalar(@{$gid{$_}}) > 1){
        $msg .= scalar(@{$gid{$_}}) . " users with GID '$_' found: " . join(",", sort @{$gid{$_}}) . ". ";
        quit "CRITICAL", $msg;
    }
}
##############################

my @users_not_found;
my @user_duplicates;
my @groups_not_found;
my @group_duplicates;
my $found;

# The reason I fetch each user is because getent behaves differently when enumerating all users vs a single user
# and the single user scenario is the one that affects authentication, so until that works, your LDAP login isn't going to
foreach(@users){
    #$found = inArray($_, @users_present);
    $found = getent("passwd", $_);
    unless($found) {
        push(@users_not_found, $_);
        next;
    }
    push(@user_duplicates, $_) if($found>1);
}
foreach(@groups){
    #$found = inArray($_, @groups_present);
    $found = getent("group", $_);
    unless($found) {
        push(@groups_not_found, $_);
        next;
    }
    push(@group_duplicates, $_) if($found>1);
}
if(@users_not_found){
    critical();
    plural(\@users_not_found);
    $msg .= scalar @users_not_found . " user$plural not found: " . join(",", sort @users_not_found) . ". ";
}

if(@user_duplicates){
    critical();
    plural(\@user_duplicates);
    $msg .= scalar @user_duplicates . " user$plural duplicates: " . join(",", sort @user_duplicates) . ". ";
}

if(@groups_not_found){
    critical();
    plural(\@groups_not_found);
    $msg .= scalar @groups_not_found . " group$plural not found: " . join(",", sort @groups_not_found) . ". ";
}

if(@group_duplicates){
    critical();
    plural(\@group_duplicates);
    $msg .= scalar @group_duplicates . " group$plural duplicates: " . join(",", sort @group_duplicates) . ". ";
}

plural(\@users);
$msg .= @users . " user$plural";
plural(\@groups);
$msg .= ", " . @groups . " group$plural" if @groups;
$msg .= " checked";
if($verbose){
    $msg .= " (users:" . join(",", sort @users);
    $msg .= " / groups:" . join(",", sort @groups) if @groups;
    $msg .= ")";
}

if($groups_file and @groups_allowed){
    my %groups_found;
    my @groups_missing;
    my @groups_unauthorized;
    my $msg2 = "";
    my $fh = open_file($groups_file);
    while(<$fh>){
        chomp;
        vlog3($_);
        s/#.*$//;
        next if /^\s*$/;
        s/^\s*//;
        s/\s*$//;
        $groups_found{$_} = 1;
    }
    vlog2("checking groups file '$groups_file' for expected groups");
    foreach(@groups_allowed){
        vlog2("checking groups file for $_");
        unless(exists $groups_found{$_}){
            critical();
            push(@groups_missing, $_);
        }
    }
    vlog2("checking groups file for any unauthorized groups");
    foreach my $found_group (sort keys %groups_found){
        if ( not grep { $_ eq $found_group} @groups_allowed ){
            critical();
            push(@groups_unauthorized, $found_group);
        }
    }
    plural(\@groups_missing);
    $msg2 .= scalar(@groups_missing) . " group$plural missing" if @groups_missing;
    $msg2 .= ", " if(@groups_missing and @groups_unauthorized);
    plural(\@groups_unauthorized);
    $msg2 .= scalar(@groups_unauthorized) . " unauthorized group$plural" if @groups_unauthorized;
    $msg2 .= " in '$groups_file'! (" if(@groups_missing or @groups_unauthorized);
    $msg2 .= "missing:" . join(",", @groups_missing) if @groups_missing;
    $msg2 .= ", " if(@groups_missing and @groups_unauthorized);
    $msg2 .= "unauthorized:" . join(",", @groups_unauthorized) if @groups_unauthorized;
    $msg2 .= ")" if(@groups_missing or @groups_unauthorized);
    $msg = "$msg2. $msg" if $msg2;
    $msg .= ". " . scalar(@groups_allowed) . " authorized groups checked";
    $msg .= " (" . join(",", @groups_allowed) . ")" if $verbose;
}

quit $status, $msg;
