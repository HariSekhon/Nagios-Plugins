#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-07-25 14:57:36 +0100 (Mon, 25 Jul 2016)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

"""

Nagios Plugin to check a Git checkout is in the right branch

Port of Perl version originally written for puppetmasters to make sure prod
and staging environment dirs had the right branches checked out in them

Requires the 'git' command in the $PATH, otherwise you can set the path to the git
executable using the environment variable GIT_PYTHON_GIT_EXECUTABLE

See also check_git_checkout_branch.pl

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import re
import sys
import traceback
import git
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import CriticalError, log_option, validate_directory
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.2'


class CheckGitCheckoutBranch(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGitCheckoutBranch, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'CheckGitCheckoutBranch msg not defined'

    def add_options(self):
        self.add_opt('-d', '--directory', action='store', help='Path to git checkout directory')
        self.add_opt('-b', '--branch', action='store', help='Branch to expect in git checkout directory')

    def run(self):
        self.no_args()
        directory = self.get_opt('directory')
        validate_directory(directory)
        directory = os.path.abspath(directory)
        expected_branch = self.get_opt('branch')
        if expected_branch is None:
            self.usage('expected branch not defined')
        if not re.match(r'^[\w\s-]+$', expected_branch):
            self.usage('Invalid branch name given, must be alphanumeric' + \
                       ', may contain dashes and spaces for detached HEADs')
        log_option('expected branch', expected_branch)
        try:
            repo = git.Repo(directory)
        except git.InvalidGitRepositoryError as _:
            raise CriticalError("directory '{}' does not contain a valid Git repository!".format(directory))
        try:
            current_branch = repo.active_branch.name
        # happens with detached HEAD checkout like Travis CI does
        except TypeError as _:
            raise CriticalError(_)
        if current_branch == expected_branch:
            self.ok()
            self.msg = "git branch '{0}' currently checked out in directory '{1}'"\
                       .format(current_branch, directory)
        else:
            raise CriticalError("git branch '{current_branch}' checked out".format(current_branch=current_branch) +
                                ", expecting branch '{expected_branch}' in directory '{directory}'"
                                .format(expected_branch=expected_branch,
                                        directory=directory))


if __name__ == '__main__':
    CheckGitCheckoutBranch().main()
