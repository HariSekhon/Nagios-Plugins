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

Nagios Plugin to check Travis CI last build status for a given repository via the Travis API

Checks for the last finished build:

- status = PASSED/FAILED
- build number (integer)
- build duration in seconds
  - optional --warning / --critical thresholds for build duration
- build start and finished date & time.

Perfdata is output for build time for the last finished build and number of current builds in progress.

Verbose mode gives extra info including commit id, commit message, repository id and number of builds in progress

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
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log
    from harisekhon.utils import UnknownError
    from harisekhon.utils import validate_chars, jsonpp
    from harisekhon.utils import isInt, qquit, plural, support_msg_api
    from harisekhon import NagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.6.0'


class CheckTravisCILastBuild(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckTravisCILastBuild, self).__init__()
        # Python 3.x
        # super().__init__()
        self.repo = None
        self.msg = "No Message Defined"
        self.builds_in_progress = 0

    def add_options(self):
        self.add_opt('-r', '--repo', default=os.getenv('TRAVIS_REPO'),
                     help="Travis repo ($TRAVIS_REPO, 'user/repo' eg. 'HariSekhon/nagios-plugins'" + \
                          ", this is case sensitive due to the Travis API)")
        self.add_thresholds()

    def process_args(self):
        self.no_args()
        self.repo = self.get_opt('repo')
        if self.repo is None:
            self.usage('--repo not defined')
        parts = self.repo.split('/')
        if len(parts) != 2 or not parts[0] or not parts[1]:
            self.usage("invalid --repo format, must be in form of 'user/repo'")
        validate_chars(self.repo, 'repo', r'\/\w\.-')
        self.validate_thresholds(optional=True)

    def run(self):
        url = 'https://api.travis-ci.org/repos/{repo}/builds'.format(repo=self.repo)
        request_handler = RequestHandler()
        req = request_handler.get(url)
        if log.isEnabledFor(logging.DEBUG):
            log.debug("\n%s", jsonpp(req.content))
        try:
            self.parse_results(req.content)
        except (KeyError, ValueError):
            exception = traceback.format_exc().split('\n')[-2]
            # this covers up the traceback info and makes it harder to debug
            #raise UnknownError('failed to parse expected json response from Travis CI API: {0}'.format(exception))
            qquit('UNKNOWN', 'failed to parse expected json response from Travis CI API: {0}. {1}'.
                  format(exception, support_msg_api()))

    def get_latest_build(self, content):
        build = None
        builds = json.loads(content)
        if not builds:
            qquit('UNKNOWN', "no Travis CI builds returned by the Travis API."
                  + " Either the specified repo '{0}' doesn't exist".format(self.repo)
                  + " or no builds have happened yet?"
                  + " Also remember the repo is case sensitive, for example 'harisekhon/nagios-plugins' returns this"
                  + " blank build set whereas 'HariSekhon/nagios-plugins' succeeds"
                  + " in returning latest builds information"
                 )
        # get latest finished build
        last_build_number = None
        for _ in builds:
            # API returns most recent build first so just take the first one that is completed
            # extra check to make sure we're getting the very latest build number and API hasn't changed
            build_number = _['number']
            if not isInt(build_number):
                raise UnknownError('build number returned is not an integer!')
            build_number = int(build_number)
            if last_build_number is None:
                last_build_number = int(build_number) + 1
            if build_number >= last_build_number:
                raise UnknownError('build number returned is out of sequence, cannot be >= last build returned' + \
                                   '{0}'.format(support_msg_api()))
            last_build_number = build_number
            if _['state'] == 'finished':
                if build is None:
                    build = _
                    # don't break as we want to count builds in progress
                    # and also check the build numbers keep descending so we have the first latest build
                    #break
            else:
                self.builds_in_progress += 1
        if build is None:
            qquit('UNKNOWN', 'no recent builds finished yet')
        if log.isEnabledFor(logging.DEBUG):
            log.debug("latest build:\n%s", jsonpp(build))
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

        self.msg = "Travis CI build #{number} {status} for repo '{repo}' in {duration} secs".format(\
                               number=number, status=status, repo=self.repo, duration=duration)
        self.check_thresholds(duration)
        self.msg += ", started_at='{0}'".format(started_at)
        self.msg += ", finished_at='{0}'".format(finished_at)

        if self.verbose:
            self.msg += ", message='{0}'".format(message)
            self.msg += ", branch='{0}'".format(branch)
            self.msg += ", commit='{0}'".format(commit)
            self.msg += ", repository_id='{0}'".format(repository_id)

        if self.verbose or self.builds_in_progress > 0:
            self.msg += ", {0} build{1} in progress".format(self.builds_in_progress, plural(self.builds_in_progress))
        self.msg += " | last_build_duration={duration}s{perf_thresholds} num_builds_in_progress={builds_in_progress}"\
                    .format(duration=duration,
                            perf_thresholds=self.get_perf_thresholds(),
                            builds_in_progress=self.builds_in_progress)


if __name__ == '__main__':
    CheckTravisCILastBuild().main()
