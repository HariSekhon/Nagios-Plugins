#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: Tue Sep 26 09:24:25 CEST 2017
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

Nagios Plugin to check an Apache Ranger repository via Ranger Admin's REST API

Tests a repository found either either name or id with the following checks:

- repository exists
- repository active (enabled)
- repository last update time is less than N minutes --warning / --critical thresholds (to catch repo changes, optional)
  - (you can go to Ranger Admin UI -> Audit -> Admin to see what actual changes were made when this alert is triggered)
- repository type (eg. hive, hdfs)

The query for this is targeted by --name and / or --id for efficiency but if you give a non-existent repository
ID you will get a more generic 204 No Content critical error result as that is what is returned by Ranger

If specifying both a repository --id (which you can find via --list-repositories) and also a repository --name
then the name will be validated against the returned repository if one is found by targeted id query

Tested on HDP 2.6.1 (Ranger 0.7.0)

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

from datetime import datetime
import math
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import isList
    from harisekhon.utils import ERRORS, CriticalError, UnknownError
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2.2'


class CheckRangerRepository(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRangerRepository, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop Ranger', 'Ranger', 'Hadoop']
        self.path = '/service/public/api/repository'
        self.default_port = 6080
        self.json = True
        self.auth = True
        self.msg = 'Ranger Message Not Defined'
        self.repository_name = None
        self.repository_id = None
        self.no_audit = False
        self.recursive = False
        self.type = None
        self.list_repositories = False

    def add_options(self):
        super(CheckRangerRepository, self).add_options()
        self.add_opt('-n', '--name', help='Repository name to expect to find')
        self.add_opt('-i', '--id', help='Repository ID to expect to find')
        self.add_opt('-T', '--type', help='Repository type to expect repository to belong to')
        self.add_opt('-l', '--list-repositories', action='store_true', help='List Ranger repositories and exit')
        self.add_thresholds(default_warning=60)

    def process_options(self):
        super(CheckRangerRepository, self).process_options()

        self.repository_name = self.get_opt('name')
        self.repository_id = self.get_opt('id')
        self.type = self.get_opt('type')
        self.list_repositories = self.get_opt('list_repositories')

        if not self.list_repositories:
            if not self.repository_name and not self.repository_id:
                self.usage('--repository name / --repository-id is not defined')

        # TODO: should technically iterate over pages for --list...
        if not self.list_repositories:
            if self.repository_id:
                self.path += '/{0}'.format(self.repository_id)
            if self.repository_name:
                self.path += '?name={0}'.format(self.repository_name)

        self.validate_thresholds(simple='lower', optional=True)

    # TODO: extract msgDesc from json error response

    def parse_json(self, json_data):
        repository = None
        if self.repository_id:
            repository = json_data
            repository_list = [repository]
        if not self.repository_id or self.list_repositories:
            repository_list = json_data['vXRepositories']
        if not repository_list:
            raise CriticalError('Ranger repository not found! (check the --name is correct and that it really exists)')
        host_info = ''
        if self.verbose:
            host_info = " at '{0}:{1}'".format(self.host, self.port)
        if not isList(repository_list):
            raise UnknownError("non-list returned for json_data[vXRepositories] by Ranger{0}"\
                               .format(host_info))
        if self.list_repositories:
            self.print_repositories(repository_list)
            sys.exit(ERRORS['UNKNOWN'])

        if repository is None and self.repository_name:
            for _ in repository_list:
                if _['name'] == self.repository_name:
                    repository = _
                    break
        # this won't apply when --id is given as it's a targeted query that will get 404 before this
        # will only apply to --name based queries
        if not repository:
            raise CriticalError("no matching repository found with name '{name}' in repository list "\
                                .format(name=self.repository_name) +
                                "returned by Ranger{host_info}".format(host_info=host_info))

        self.check_repository(repository)

    def check_repository(self, repository):
        repository_name = repository['name']
        repository_id = repository['id']
        if self.repository_id:
            if str(repository_id) != str(self.repository_id):
                raise UnknownError('repository id {} differs from id queried'.format(repository_id))
        self.msg = "Ranger repository id '{0}' name '{1}'".format(repository_id, repository_name)
        if self.repository_name is not None and self.repository_name != repository_name:
            self.critical()
            self.msg += " (expected '{0}')".format(self.repository_name)
        active = repository['isActive']
        self.msg += ', active = {0}'.format(active)
        if not active:
            self.critical()
            self.msg += ' (expected True)'
        repo_type = repository['repositoryType']
        self.msg += ", type = '{0}'".format(repo_type)
        if self.type and self.type != repo_type:
            self.critical()
            self.msg += " (expected '{0}')".format(self.type)
        last_updated = repository['updateDate']
        last_updated_by = repository['updatedBy']
        # in case it's null and was never updated skip this bit
        if last_updated:
            last_updated_datetime = datetime.strptime(last_updated, '%Y-%m-%dT%H:%M:%SZ')
            self.msg += ", last updated = '{0}'".format(last_updated)
            # looks like Ranger timestamp is in UTC, if it isn't it should be that's best practice for timestamps
            timedelta = datetime.utcnow() - last_updated_datetime
            # ensure we don't round down to zero mins and pass the check, round up in mins
            mins_ago_int = int(math.ceil(timedelta.total_seconds() / 60.0))
            mins_ago = '{0:d}'.format(mins_ago_int)
            self.msg += ", {0} mins ago".format(mins_ago)
            self.check_thresholds(mins_ago)
            self.msg += ' by {0}'.format(last_updated_by)

    @staticmethod
    def print_repositories(repository_list):
        cols = {
            'Name': 'name',
            'RepoType': 'repositoryType',
            'Description': 'description',
            'Active': 'isActive',
            'Id': 'id',
        }
        widths = {}
        for col in cols:
            widths[col] = len(col)
        for _ in repository_list:
            for col in cols:
                if col == 'Description':
                    continue
                if col not in widths:
                    widths[col] = 0
                width = len(str(_[cols[col]]))
                if width > widths[col]:
                    widths[col] = width
        total_width = 0
        columns = ('Id', 'Name', 'RepoType', 'Active', 'Description')
        for heading in columns:
            total_width += widths[heading] + 2
        print('=' * total_width)
        for heading in columns:
            print('{0:{1}}  '.format(heading, widths[heading]), end='')
        print()
        print('=' * total_width)
        for _ in repository_list:
            for col in columns:
                print('{0:{1}}  '.format(_[cols[col]], widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckRangerRepository().main()
