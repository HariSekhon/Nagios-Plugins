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

Nagios Plugin to check a Git working copy doesn't have untracked files

Written for environments where deployment servers are running off Git checkouts
to ensure that any new or changed config or code has been backported to Git

Checks:

- uncommitted unstaged changes
- untracked files
- if neither of the above are detected
  - then checks for staged but uncommitted changes to catch this final edge condition

Requires the 'git' command in the $PATH, otherwise you can set the path to the git
executable using the environment variable GIT_PYTHON_GIT_EXECUTABLE

See also check_git_checkout_branch.py
         check_git_checkout_dirty.py

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
    from harisekhon.utils import CriticalError, validate_directory, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.1'


class CheckGitUncommittedChanges(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGitUncommittedChanges, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'CheckGitUncommittedChanges msg not defined'
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
        except git.InvalidGitRepositoryError as _:
            raise CriticalError("directory '{}' does not contain a valid Git repository!".format(directory))
        try:
            untracked_files = repo.untracked_files
            num_untracked_files = len(untracked_files)
            changed_files = [item.a_path for item in repo.index.diff(None)]
            changed_files = [filename for filename in changed_files if filename not in untracked_files]
            num_changed_files = len(changed_files)
        except git.InvalidGitRepositoryError as _:
            raise CriticalError(_)
        except TypeError as _:
            raise CriticalError(_)
        self.msg = '{} changed file{}'.format(num_changed_files, plural(num_changed_files))
        self.msg += ', {} untracked file{}'.format(num_untracked_files, plural(num_untracked_files))
        self.msg += " in Git checkout at directory '{}'".format(directory)
        uncommitted_staged_changes = 0
        if changed_files or untracked_files:
            self.critical()
            if self.verbose:
                if changed_files:
                    self.msg += ' (changed files: {})'.format(', '.join(changed_files))
                if untracked_files:
                    self.msg += ' (untracked files: {})'.format(', '.join(untracked_files))
        elif repo.is_dirty():
            self.msg += ', uncommitted staged changes detected!'
            self.critical()
            uncommitted_staged_changes = 1
        self.msg += ' | changed_files={};0;0 untracked_files={};0;0'.format(num_changed_files, num_untracked_files)
        self.msg += ' uncommitted_staged_changes={};0;0'.format(uncommitted_staged_changes)


if __name__ == '__main__':
    CheckGitUncommittedChanges().main()
