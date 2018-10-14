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

Nagios Plugin to check an Apache Ranger policy via Ranger Admin's REST API

Tests a policy found either either name or id with the following checks:

- policy exists
- policy enabled
- policy has auditing (can disable audit check)
- policy is recursive (optional)
- policy last update time is less than N minutes --warning / --critical thresholds (to catch policy changes, optional)
  - (you can go to Ranger Admin UI -> Audit -> Admin to see what actual changes were made when this alert is triggered)
- repository name the policy belongs to (optional)
- repository type the policy belongs to (eg. hive, hdfs - optional)

Will output repository name and type in verbose mode or outputs each one if a check is specified against it.

Queries are targeted by --id and / or --name for efficiency but if you give a non-existent policy ID
you will get a more generic 404 Not Found r 400 Bad Request critical error result as that is what is returned by Ranger

If specifying a policy --id (which you can find via --list-policies) and also specifying a policy --name
then the name will be validated against the returned policy if one is found by targeted id query

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
__version__ = '0.3.2'


class CheckRangerPolicy(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckRangerPolicy, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop Ranger', 'Ranger', 'Hadoop']
        self.path = '/service/public/api/policy'
        self.default_port = 6080
        self.json = True
        self.auth = True
        self.msg = 'Ranger Message Not Defined'
        self.policy_name = None
        self.policy_id = None
        self.no_audit = False
        self.recursive = False
        self.repo_details = {'repo_name': None, 'repo_type': None}
        self.list_policies = False

    def add_options(self):
        super(CheckRangerPolicy, self).add_options()
        self.add_opt('-n', '--name', help='Policy name to expect to find')
        self.add_opt('-i', '--id', help='Policy ID to expect to find')
        self.add_opt('-a', '--no-audit', action='store_true', help='Do not require auditing to be enabled')
        self.add_opt('-r', '--recursive', action='store_true', help='Checks the policy is set to recursive')
        self.add_opt('--repo-name', help='Repository name to expect policy to belong to')
        self.add_opt('--repo-type', help='Repository type to expect policy to belong to')
        self.add_opt('-l', '--list-policies', action='store_true', help='List Ranger policies and exit')
        self.add_thresholds()

    def process_options(self):
        super(CheckRangerPolicy, self).process_options()

        self.policy_name = self.get_opt('name')
        self.policy_id = self.get_opt('id')
        self.no_audit = self.get_opt('no_audit')
        self.recursive = self.get_opt('recursive')
        self.repo_details['repo_name'] = self.get_opt('repo_name')
        self.repo_details['repo_type'] = self.get_opt('repo_type')
        self.list_policies = self.get_opt('list_policies')

        if not self.list_policies:
            if not self.policy_name and not self.policy_id:
                self.usage('--policy name / --policy-id is not defined')

        # TODO: should technically iterate over pages if --list...
        if not self.list_policies:
            if self.policy_id:
                self.path += '/{0}'.format(self.policy_id)
            if self.policy_name:
                self.path += '?policyName={0}'.format(self.policy_name)

        self.validate_thresholds(simple='lower', optional=True)

    # TODO: extract msgDesc from json error response

    def parse_json(self, json_data):
        policy = None
        if self.policy_id:
            policy = json_data
            policy_list = [policy]
        if not self.policy_id or self.list_policies:
            policy_list = json_data['vXPolicies']
        if not policy_list:
            raise CriticalError('Ranger policy not found! (check the --name is correct and that it really exists)')
        host_info = ''
        if self.verbose:
            host_info = " at '{0}:{1}'".format(self.host, self.port)
        if not isList(policy_list):
            raise UnknownError("non-list returned for json_data[vXPolicies] by Ranger{0}"\
                               .format(host_info))
        if self.list_policies:
            self.print_policies(policy_list)
            sys.exit(ERRORS['UNKNOWN'])

        if policy is None and self.policy_name:
            for _ in policy_list:
                if _['policyName'] == self.policy_name:
                    policy = _
                    break
        # this won't apply when --policy-id is given as it's a targeted query that will get 404 before this
        if not policy:
            raise CriticalError("no matching policy found with name '{name}' in policy list "\
                                .format(name=self.policy_name) +
                                "returned by Ranger{host_info}".format(host_info=host_info))

        self.check_policy(policy)

    def check_policy(self, policy):
        policy_name = policy['policyName']
        policy_id = policy['id']
        if self.policy_id:
            if str(policy_id) != str(self.policy_id):
                raise UnknownError('policy id {} differs from that queried'.format(policy_id))
        self.msg = "Ranger policy id '{0}' name '{1}'".format(policy_id, policy_name)
        if self.policy_name is not None and self.policy_name != policy_name:
            self.critical()
            self.msg += " (expected '{0}')".format(self.policy_name)
        enabled = policy['isEnabled']
        auditing = policy['isAuditEnabled']
        recursive = policy['isRecursive']
        self.msg += ', enabled = {0}'.format(enabled)
        if not enabled:
            self.critical()
            self.msg += ' (expected True)'
        self.msg += ', auditing = {0}'.format(auditing)
        if not auditing and not self.no_audit:
            self.critical()
            self.msg += ' (expected True)'
        self.msg += ', recursive = {0}'.format(recursive)
        if self.recursive and not recursive:
            self.critical()
            self.msg += ' (expected True)'
        opts = {
            'repo_name': policy['repositoryName'],
            'repo_type': policy['repositoryType']
        }
        for _ in ('name', 'type'):
            detail = 'repo_{0}'.format(_)
            expected_result = self.repo_details[detail]
            result = opts['repo_{0}'.format(_)]
            if self.verbose or expected_result:
                self.msg += ", repo {0} = '{1}'".format(_, result)
                if expected_result and expected_result != result:
                    self.critical()
                    self.msg += " (expected '{0}')".format(expected_result)
        last_updated = policy['updateDate']
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

    @staticmethod
    def print_policies(policy_list):
        cols = {
            'Name': 'policyName',
            'RepoName': 'repositoryName',
            'RepoType': 'repositoryType',
            'Description': 'description',
            'Enabled': 'isEnabled',
            'Audit': 'isAuditEnabled',
            'Recursive': 'isRecursive',
            'Id': 'id',
        }
        widths = {}
        for col in cols:
            widths[col] = len(col)
        for _ in policy_list:
            for col in cols:
                if col == 'Description':
                    continue
                if col not in widths:
                    widths[col] = 0
                width = len(str(_[cols[col]]))
                if width > widths[col]:
                    widths[col] = width
        total_width = 0
        columns = ('Id', 'Name', 'RepoName', 'RepoType', 'Enabled', 'Audit', 'Recursive', 'Description')
        for heading in columns:
            total_width += widths[heading] + 2
        print('=' * total_width)
        for heading in columns:
            print('{0:{1}}  '.format(heading, widths[heading]), end='')
        print()
        print('=' * total_width)
        for _ in policy_list:
            for col in columns:
                print('{0:{1}}  '.format(_[cols[col]], widths[col]), end='')
            print()


if __name__ == '__main__':
    CheckRangerPolicy().main()
