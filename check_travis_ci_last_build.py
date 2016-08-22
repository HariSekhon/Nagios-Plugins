#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-08-12 20:45:24 +0100 (Fri, 12 Aug 2016)
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

Nagios Plugin to check the last build status of a given Travis CI repository via the Travis API

Use --verbose to give extra information about the latest build, -vv for multi-line info, and -vvv or -D for debug output

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import json
import logging
import os
import sys
import traceback
try:
    import requests
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log
    from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.utils import validate_chars, jsonpp
    from harisekhon.utils import isInt, qquit
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckTravisCILastBuild(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTravisCILastBuild, self).__init__()
        # Python 3.x
        # super().__init__()
        self.repo = None
        self.msg = "No Message Defined"

    def add_options(self):
        self.add_opt('-r', '--repo',
                     help="Travis repo (case sensitive, in form of 'user/repo' eg. 'HariSekhon/nagios-plugins')")

    def process_args(self):
        self.no_args()
        self.repo = self.get_opt('repo')
        if self.repo is None:
            self.usage('--repo not defined')
        parts = self.repo.split('/')
        if len(parts) != 2 or not parts[0] or not parts[1]:
            self.usage("--repo format invalid, must be in form of 'user/repo'")
        validate_chars(self.repo, 'repo', r'\/\w\.-')

    def run(self):
        url = 'https://api.travis-ci.org/repos/{repo}/builds'.format(repo=self.repo)
        log.debug('GET %s' % url)
        try:
            req = requests.get(url)
        except requests.exceptions.RequestException as _:
            raise CriticalError(_)
        log.debug("response: %s %s", req.status_code, req.reason)
        log.debug("content:\n%s\n%s\n%s", '='*80, req.content.strip(), '='*80)
        if req.status_code != 200:
            raise CriticalError("%s %s" % (req.status_code, req.reason))
        if log.isEnabledFor(logging.DEBUG):
            log.debug("\n{0}".format(jsonpp(req.content)))
        try:
            self.parse_results(req.content)
        except (KeyError, ValueError) as _:
            exception = traceback.format_exc().split('\n')[-2]
            # this covers up the traceback info and makes it harder to debug
            #raise CriticalError('failed to parse expected json response from Travis CI API: {0}'.format(exception))
            qquit('UNKNOWN', 'failed to parse expected json response from Travis CI API: {0}'.format(exception))

    @staticmethod
    def get_latest_build(content):
        build = None
        builds = json.loads(content)
        if not builds:
            qquit('UNKNOWN', "no Travis CI builds returned by the Travis API, perhaps no builds have happened yet?" +
                  "Also remember the repo is case sensitive, for example 'harisekhon/nagios-plugins' returns this" +
                  "blank build set whereas 'HariSekhon/nagios-plugins' succeeds in returning latest builds information")
        # get latest finished build
        for _ in builds:
            if _['state'] == 'finished':
                build = _
                break
        if build is None:
            qquit('UNKNOWN', 'no recent builds finished yet')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("latest build:\n{0}".format(jsonpp(build)))
        return build

    def parse_results(self, content):
        build = self.get_latest_build(content)

        number = build['number']
        log.info('build number = %s', number)
        if not isInt(number):
            raise UnknownError('build number returned is not an integer!')

        message = build['message']
        log.info('message = %s', message)

        branch = build['branch']
        log.info('branch = %s', branch)

        commit = build['commit']
        log.info('commit = %s', commit)

        started_at = build['started_at']
        log.info('started_at  = %s', started_at)

        finished_at = build['finished_at']
        log.info('finished_at = %s', finished_at)

        duration = build['duration']
        log.info('duration = %s', duration)
        if not isInt(duration):
            raise UnknownError('duration returned is not an integer!')

        repository_id = build['repository_id']
        log.info('repository_id = %s', repository_id)
        if not isInt(repository_id):
            raise UnknownError('repository_id returned is not an integer!')

        result = build['result']
        log.info('result = %s', result)

        state = build['state']
        log.info('state = %s', state)

        if result == 0:
            self.ok()
            status = "PASSED"
        else:
            self.critical()
            status = "FAILED"

        self.msg = "Travis CI build #{number} {status} for repo '{repo}' in {duration} secs".format(
            number=number, status=status, repo=self.repo, duration=duration)
        self.msg += ", started_at='%s'" % started_at
        self.msg += ", finished_at='%s'" % finished_at

        if self.verbose > 0:
            self.msg += ", message='%s'" % message
            self.msg += ", branch='%s'" % branch
            self.msg += ", commit='%s'" % commit
            self.msg += ", repository_id='%s'" % repository_id

        self.msg += " | build_duration=%ss" % duration


if __name__ == '__main__':
    CheckTravisCILastBuild().main()
