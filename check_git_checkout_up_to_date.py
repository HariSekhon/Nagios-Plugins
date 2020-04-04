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

Nagios Plugin to check a Git checkout is sync'd with the upstream remote / origin

Upstream tracking branch must be named the same as the current branch

Fetching remote branch update can be slow over the network, so you may need to increase --timeout or else use --no-fetch
but beware that means you will not detect when you are commits behind the remote origin, only commits that aren't pushed
can be detected in that case

Requires the 'git' command in the $PATH, otherwise you can set the path to the git
executable using the environment variable GIT_PYTHON_GIT_EXECUTABLE

See also check_git_checkout_branch.py

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
    from harisekhon.utils import CriticalError, log, validate_directory, validate_chars
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1.1'


class CheckGitCheckoutUpToDate(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckGitCheckoutUpToDate, self).__init__()
        # Python 3.x
        # super().__init__()
        self.remote = 'origin'
        self.msg = 'CheckGitCheckoutUpToDate msg not defined'

    def add_options(self):
        self.add_opt('-d', '--directory', action='store', help='Path to git checkout directory')
        self.add_opt('-r', '--remote', default=self.remote,
                     help='Remote to check against (default: {})'.format(self.remote))
        self.add_opt('-f', '--no-fetch', action='store_true',
                     help="Don't git fetch from remote (it's slow sometimes, " + \
                          "but this means you may not detect when you are commits behind upstream)")

    def run(self):
        self.no_args()
        directory = self.get_opt('directory')
        validate_directory(directory)
        directory = os.path.abspath(directory)
        self.remote = self.get_opt('remote')
        validate_chars(self.remote, 'remote', r'A-Za-z0-9_\.-')
        try:
            repo = git.Repo(directory)
        except git.InvalidGitRepositoryError as _:
            raise CriticalError("directory '{}' does not contain a valid Git repository!".format(directory))
        try:
            if not self.get_opt('no_fetch'):
                log.info('fetching from remote repo: {}'.format(self.remote))
                repo.git.fetch(self.remote)
            branch = repo.active_branch
            log.info('active branch: %s', branch)
            commits_behind = repo.iter_commits('{branch}..{remote}/{branch}'.format(remote=self.remote, branch=branch))
            commits_ahead = repo.iter_commits('{remote}/{branch}..{branch}'.format(remote=self.remote, branch=branch))
            num_commits_behind = sum(1 for c in commits_behind)
            num_commits_ahead = sum(1 for c in commits_ahead)
        # happens with detached HEAD checkout like Travis CI does
        except TypeError as _:
            raise CriticalError(_)
        except git.GitCommandError as _:
            raise CriticalError(', '.join(str(_.stderr).split('\n')))
        self.msg = "git checkout branch '{}' is ".format(branch)
        if num_commits_ahead + num_commits_behind == 0:
            self.ok()
            self.msg += 'up to date with'
        else:
            self.critical()
            self.msg += '{} commits behind, {} commits ahead of'.format(num_commits_behind, num_commits_ahead)
        self.msg += " remote '{}'".format(self.remote)
        self.msg += ' | commits_behind={};0;0 commits_ahead={};0;0'.format(num_commits_behind, num_commits_ahead)

if __name__ == '__main__':
    CheckGitCheckoutUpToDate().main()
