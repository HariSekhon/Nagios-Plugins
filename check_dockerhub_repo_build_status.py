#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-08-30 17:44:03 +0200 (Wed, 30 Aug 2017)
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

Nagios Plugin to check the last completed build status of a DockerHub Automated build repo

If you supply an invalid repository you will get a 404 NOT FOUND returned by the DockerHub API

Only works on DockerHub Automated Builds
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

import datetime
import json
import logging
import os
import sys
import time
import traceback
#import urllib
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, validate_chars, isInt, jsonpp, sec2human
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon import NagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckDockerhubRepoBuildStatus(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerhubRepoBuildStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.request = RequestHandler()
        self.statuses = {
            '0': 'Success',
            '10': 'Success',
            '-4': 'Cancelled',
            # Not sure why these different exit codes both show simply as Error in UI
            '-1': 'Error',
            '3': 'Error'
        }
        self.msg = 'DockerHub repo '
        self.repo = None
        self.query_time = None
        self.ok()

    def add_options(self):
        self.add_opt('-r', '--repo',
                     help="DockerHub repository to check, in form of '<user>/<repo>' eg. harisekhon/pytools")

    def run(self):
        self.repo = self.get_opt('repo')
        validate_chars(self.repo, 'repo', 'A-Za-z0-9/-')

        # official repos don't have slashes in them but then you can't check their build statuses either
        if '/' not in self.repo:
            self.usage('--repo must contain a slash (/) in it - ' + \
                       'official repos are not supported as DockerHub doesn\'t expose their build info')

        #(user, repo) = self.repo.split('/', 1)
        #repo = urllib.quote_plus(repo)
        #self.repo = '{0}/{1}'.format(user, repo)

        url = 'https://registry.hub.docker.com/v2/repositories/{repo}/buildhistory'.format(repo=self.repo)

        start_time = time.time()
        req = self.request.get(url)
        self.query_time = time.time() - start_time

        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(req.content))

        json_data = json.loads(req.content)
        self.process_results(json_data)

    def process_results(self, json_data):
        result = json_data['results'][0]

        _id = result['id']
        log.info('latest build id: %s', _id)

        status = result['status']
        log.info('status: %s', status)
        if not isInt(status, allow_negative=True):
            raise UnknownError('non-integer status returned by DockerHub API. {0}'.format(support_msg_api()))

        tag = result['dockertag_name']
        log.info('tag: %s', tag)

        trigger = result['cause']
        log.info('trigger: %s', trigger)

        created_date = result['created_date']
        log.info('created date: %s', created_date)

        last_updated = result['last_updated']
        log.info('last updated: %s', last_updated)

        created_datetime = datetime.datetime.strptime(created_date.split('.')[0], '%Y-%m-%dT%H:%M:%S')
        updated_datetime = datetime.datetime.strptime(last_updated.split('.')[0], '%Y-%m-%dT%H:%M:%S')
        build_latency_timedelta = updated_datetime - created_datetime
        build_latency = build_latency_timedelta.total_seconds()
        log.info('build latency (creation to last updated): %s', build_latency)
        # results in .0 floats anyway
        build_latency = int(build_latency)

        build_code = result['build_code']
        build_url = 'https://hub.docker.com/r/{0}/builds/{1}'.format(self.repo, build_code)
        log.info('latest build URL: %s', build_url)

        if str(status) in self.statuses:
            status = self.statuses[str(status)]
        else:
            log.warning("status code '%s' not recognized! %s", status, support_msg_api())
            log.warning('defaulting to assume status is an Error')
            status = 'Error'
        if status != 'Success':
            self.critical()
        self.msg += "'{repo}' latest build status: {status}, tag: '{tag}', id: {id}"\
                    .format(repo=self.repo, status=status, tag=tag, id=_id)
        if self.verbose:
            self.msg += ', trigger: {0}'.format(trigger)
            self.msg += ', created date: {0}'.format(created_date)
            self.msg += ', last updated: {0}'.format(last_updated)
            self.msg += ', build_latency: {0}'.format(sec2human(build_latency))
            self.msg += ', build URL: {0}'.format(build_url)
        self.msg += ' | build_latency={0:d}s query_time={1:.2f}s'.format(build_latency, self.query_time)


if __name__ == '__main__':
    CheckDockerhubRepoBuildStatus().main()
