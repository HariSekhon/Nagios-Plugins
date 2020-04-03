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

Nagios Plugin to check a Git checkout working directory isn't 'dirty' - ie has no uncommitted changes

Written for environments where deployment servers are running off Git checkouts
to ensure that any modifications have been backported to Git

Requires the 'git' command in the $PATH, otherwise you can set the path to the git
executable using the environment variable GIT_PYTHON_GIT_EXECUTABLE

Caveat: doesn't detect untracked files, see check_git_uncommitted_changes.py to cover that

See also check_git_checkout_branch.py
         check_git_uncommitted_changes.py - handles untracked files and gives better feedback, reporting and stats

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import os
import sys
import traceback
import git
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import CriticalError, validate_directory
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.1'


class CheckGitCheckoutDirty(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGitCheckoutDirty, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'CheckGitCheckoutDirty msg not defined'
        self.ok()

    def add_options(self):
        self.add_opt('-d', '--directory', action='store', help='Path to git checkout directory')

    def run(self):
        self.no_args()
        directory = self.get_opt('directory')
        validate_directory(directory)
        directory = os.path.abspath(directory)
        try:
            repo = git.Repo(directory)
        except git.InvalidGitRepositoryError:
            raise CriticalError("directory '{}' does not contain a valid Git repository!".format(directory))
        is_dirty = repo.is_dirty()
        self.msg = "git checkout dirty = '{}' for directory '{}'".format(is_dirty, directory)
        if is_dirty:
            self.critical()


if __name__ == '__main__':
    CheckGitCheckoutDirty().main()
