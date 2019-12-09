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

Nagios Plugin to check the last completed build status of a DockerHub Automated Build repo

Optionally specify a --tag to check latest build for a specific version or OS eg. 'version-1.1' or 'centos'

Returns the following information for the last completed build:

- status eg. Success / Error / Cancelled
- tag eg. latest, version-1.2, alpine, centos etc.
- build_code (this is what you see under /builds/<build_code> on the website)
- build latency (how long between build creation and last updated time ie. how long the build took)
- query time (time to query through the API and process the results)

Optionally also returns the following information in --verbose mode:

- build id
- trigger - what triggered this build eg. webhook, revision control change, API / website
- created date timestamp
- last updated date timestamp
- build latency in hours, mins, secs
- build URL to go direct to the build to see why it failed

If you supply an invalid repository you will get a 404 NOT FOUND returned by the DockerHub API

Can use --max-pages to search back further through the build history if necessary for a given tag

Caveats:

- Only works on DockerHub Automated Builds (otherwise there are no actual DockerHub builds to test)

- Builds in the 'Queued' and 'Building' states are skipped as it's only valid to check the latest completed build
  so if you've somehow triggered a lot of builds suddenly the check may not find a completed one in the first page
  of API output and will throw an UNKNOWN error citing "no completed builds found", you can tune using
  --max-pages to continue searching through more pages to find the last completed build. By default this program
  will only search the latest page for efficiency as it's likely a mistake if you can't find any completed
  build (either Success or Error) within the last 10 builds

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
    from harisekhon.utils import log, validate_chars, validate_int, isInt, \
                                 jsonpp, sec2human, plural, \
                                 UnknownError, support_msg_api
    from harisekhon import NagiosPlugin
    from harisekhon import RequestHandler
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.2'


class CheckDockerhubRepoBuildStatus(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerhubRepoBuildStatus, self).__init__()
        # Python 3.x
        # super().__init__()
        self.request = RequestHandler()
        self.statuses = {
            '0': 'Queued',
            '3': 'Building',
            '10': 'Success',
            '-1': 'Error',
            '-4': 'Cancelled',
        }
        self.msg = 'DockerHub repo '
        self.repo = None
        self.tag = None
        self.max_pages = None
        self.start_time = None
        self.ok()

    def add_options(self):
        self.add_opt('-r', '--repo',
                     help="DockerHub repository to check, in form of '<user>/<repo>' eg. harisekhon/pytools")
        self.add_opt('-T', '--tag', help='Check status of only this tag eg. latest or 2.7')
        self.add_opt('-p', '--pages', default=1, metavar='num',
                     help='Max number of API pages to iterate on to find the latest build (default: 1)' + \
                          '. If increasing this you will probably also need to increase --timeout')

    def process_options(self):
        self.repo = self.get_opt('repo')
        validate_chars(self.repo, 'repo', 'A-Za-z0-9/_-')
        # official repos don't have slashes in them but then you can't check their build statuses either
        if '/' not in self.repo:
            self.usage('--repo must contain a slash (/) in it - ' + \
                       'official repos are not supported as DockerHub doesn\'t expose their build info')
        (namespace, repo) = self.repo.split('/', 1)
        validate_chars(namespace, 'namespace', 'A-Za-z0-9_-')
        validate_chars(repo, 'repo', 'A-Za-z0-9_-')
        self.repo = '{0}/{1}'.format(namespace, repo)

        # not needed as dashes and underscores are all that validation above permits through and they
        # are returned as is and processed successfully by DockerHub API
        #(user, repo) = self.repo.split('/', 1)
        #repo = urllib.quote_plus(repo)
        #self.repo = '{0}/{1}'.format(user, repo)

        self.tag = self.get_opt('tag')
        if self.tag is not None:
            # if you have a tag which characters other than these then please raise a ticket for extension at:
            #
            #   https://github.com/harisekhon/nagios-plugins/issues
            #
            self.tag = self.tag.lstrip(':')
            validate_chars(self.tag, 'tag', r'A-Za-z0-9/\._-')
            #if not self.tag:
            #    self.usage('--tag cannot be blank if given')
        self.max_pages = self.get_opt('pages')
        # if you have to iterate more than 20 pages you have problems, and this check will take ages
        validate_int(self.max_pages, 'max pages', 1, 20)
        self.max_pages = int(self.max_pages)

    def run(self):
        start_time = time.time()
        for page in range(1, self.max_pages + 1):
            url = 'https://registry.hub.docker.com/v2/repositories/{repo}/buildhistory?page={page}'\
                  .format(repo=self.repo, page=page)
            req = self.request.get(url)
            if log.isEnabledFor(logging.DEBUG):
                log.debug(jsonpp(req.content))
            json_data = json.loads(req.content)
            log.debug('%s out of %s results returned for page %s', len(json_data['results']), json_data['count'], page)
            if self.process_results(json_data):
                # not quite as accurate as before as it now includes processing time but close enough
                query_time = time.time() - start_time
                if '|' not in self.msg:
                    self.msg += ' |'
                self.msg += ' query_time={0:.2f}s'.format(query_time)
                return True
        extra_info = ''
        if self.verbose:
            extra_info = ' ({0} page{1} of API output)'\
                         .format(self.max_pages, plural(self.max_pages))
        raise UnknownError('no completed builds found in last {0} builds{1}'.format(self.max_pages * 10, extra_info))

    def process_results(self, json_data):
        for result in json_data['results']:
            tag = result['dockertag_name']
            build_code = result['build_code']
            _id = result['id']
            # Skip Queued / Building as we're only interested in latest completed build status
            if int(result['status']) in (0, 3):
                if log.isEnabledFor(logging.DEBUG):
                    log.debug("skipping queued/in progress build tag '%s', id: %s, build_code: %s",
                              tag, _id, build_code)
                continue
            if self.tag and self.tag != tag:
                if log.isEnabledFor(logging.DEBUG):
                    log.debug("skipping build tag '%s', id: %s, build_code: %s, does not match given --tag %s",
                              tag, _id, build_code, self.tag)
                continue
            self.process_result(result)
            return True
        return False

    def process_result(self, result):
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
        self.msg += "'{repo}' last completed build status: '{status}', tag: '{tag}', build code: {build_code}"\
                    .format(repo=self.repo, status=status, tag=tag, build_code=build_code)
        if self.verbose:
            self.msg += ', id: {0}'.format(_id)
            self.msg += ', trigger: {0}'.format(trigger)
            self.msg += ', created date: {0}'.format(created_date)
            self.msg += ', last updated: {0}'.format(last_updated)
            self.msg += ', build_latency: {0}'.format(sec2human(build_latency))
            self.msg += ', build URL: {0}'.format(build_url)
        self.msg += ' | build_latency={0:d}s'.format(build_latency)


if __name__ == '__main__':
    CheckDockerhubRepoBuildStatus().main()
