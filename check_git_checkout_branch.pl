#!/usr/bin/perl -T
# nagios: -epn
#
#  Author: Hari Sekhon
#  Date: 2012-07-26 12:09:53 +0100 (Thu, 26 Jul 2012)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

$DESCRIPTION = "Nagios Plugin to check a Git checkout is in the right branch

Primarily written for puppetmasters to make sure prod and staging
environment dirs had the right branches checked out in them

See also check_git_checkout_branch.py
         check_git_checkout_dirty.py
         check_git_uncommitted_changes.py
";

$VERSION = "0.3.4";

use strict;
use warnings;
BEGIN {
    use File::Basename;
    use lib dirname(__FILE__) . "/lib";
}
use HariSekhonUtils;
use Cwd 'abs_path';

my $directory;
my $branch;
my $branch_checkout;
my $git_default = "git";
my $git = $git_default;
%options = (
    "d|directory=s" => [ \$directory, "Path to git checkout directory" ],
    "b|branch=s"    => [ \$branch,    "Branch to expect in git checkout directory" ],
    "git-binary=s"  => [ \$git,       "Path to git binary. Defaults to '$git_default'. Without relative or fully qualified path to binary will use \$PATH" ],
);
@usage_order = qw/directory branch/;

get_options();

$directory = abs_path($directory) if defined($directory);
$directory = validate_directory($directory);
$branch or usage "branch name not specified";
$branch    =~ /^([\w\s-]+)$/ or usage "Invalid branch name given, must be alphanumeric with dashes and spaces permitted for detached HEADs";
$branch    = $1;
$git       = validate_program_path($git, "git");

vlog2 "directory: $directory
branch:    $branch
";
set_timeout();

chdir($directory) or quit "CRITICAL", "Failed to chdir to directory '$directory'";
my @output = cmd("$git branch --color=never", 1);
foreach(@output){
    # parsing "(HEAD detached from 43e7b9e)"
    if(/^\*\s+\(?(.+?)\)?\s*$/){
        $branch_checkout = $1;
        last;
    }
}
defined($branch_checkout) or quit "CRITICAL", "Failed to determine current branch checkout for directory '$directory'";

if($branch_checkout eq $branch){
    quit "OK", "git branch '$branch_checkout' currently checked out in directory '$directory'";
} else {
    quit "CRITICAL", "git branch '$branch_checkout' checked out, expecting branch '$branch' in directory '$directory'";
}
