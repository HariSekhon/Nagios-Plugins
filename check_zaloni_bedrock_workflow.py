#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-10-17 14:47:08 +0100 (Mon, 17 Oct 2016)
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

Nagios Plugin to check Zaloni Bedrock workflow execution via the REST API

Checks the following for the last execution of a given workflow:

1. status
2. time taken in mins (optional)
3. age since last run in mins (optional)
4. outputs start and end times (optional)
5. perfdata for time taken and age

If specifying -A / --all then will only check the last completed execution status for each workflow as the Bedrock API
at this time of writing requires specifying a workflow name / id and does not allow a global search of all workflows to
find the latest workflow to check for runtime and age (the ingestion API does however allow this, see
check_zaloni_bedrock_ingestion.py).

Can also list all workflows with names, IDs, category, owner and modified by for easy reference

Verbose mode will output the start/end date & time of the last job as well

Version 0.4 has added to check a feature to check all workflows, use with caution as it will take O(n) time,
ie it'll take longer and longer the more workflows you have, which may exceed monitoring server execution timeouts

Tested on Zaloni Bedrock 4.1.1 with Hortonworks HDP 2.4.2
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

from datetime import datetime
#import cookielib
import json
import logging
import os
import sys
import time
import traceback
try:
    import requests
    #from requests import Request, Session
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, qquit
    #from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password, \
                                 validate_chars, validate_int, validate_float, \
                                 jsonpp, isList, isStr, ERRORS, support_msg_api, code_error, sec2human, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.3'


class CheckZaloniBedrockWorkflow(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckZaloniBedrockWorkflow, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Zaloni '
        self.protocol = 'http'
        self.host = None
        self.port = None
        self.user = None
        self.password = None
        self.url_base = None
        #self.jar = None
        self.jsessionid = None
        self.auth_time = None
        self.query_time = None
        self._all = False
        self.workflow_id = None
        self.workflow_name = None
        self.max_age = None
        self.max_runtime = None
        self.min_runtime = None
        self.ok()

    def add_options(self):
        self.add_hostoption(name='Zaloni Bedrock', default_host='localhost', default_port=8080)
        self.add_useroption(name='Zaloni Bedrock', default_user='admin')
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-A', '--all', action='store_true', help='Find and check all workflows')
        self.add_opt('-I', '--id', metavar='<int>',
                     help='Workflow ID to check (see --list or UI to find these)')
        self.add_opt('-N', '--name', metavar='<name>',
                     help='Workflow Name to check (see --list or UI to find these)')
        self.add_opt('-a', '--max-age', metavar='<mins>',
                     help='Max age in minutes since start of last workflow run (optional)')
        self.add_opt('-m', '--max-runtime', metavar='<mins>',
                     help='Max run time of last workflow in minutes (optional)')
        self.add_opt('-n', '--min-runtime', metavar='<mins>', default=0.1,
                     help='Min run time of last workflow in minutes, raises warning to catch jobs that ' + \
                     'finish suspiciously quickly (optional, default: 0.1)')
        self.add_opt('-l', '--list', action='store_true', help='List workflows and exit')

    def process_options(self):
        self.no_args()
        self.host = self.get_opt('host')
        self.port = self.get_opt('port')
        self.user = self.get_opt('user')
        self.password = self.get_opt('password')
        self._all = self.get_opt('all')
        self.workflow_id = self.get_opt('id')
        self.workflow_name = self.get_opt('name')
        self.max_age = self.get_opt('max_age')
        self.max_runtime = self.get_opt('max_runtime')
        self.min_runtime = self.get_opt('min_runtime')
        if self.get_opt('ssl'):
            self.protocol = 'https'
        validate_host(self.host)
        validate_port(self.port)
        validate_user(self.user)
        validate_password(self.password)
        if self._all and (self.workflow_name is not None or self.workflow_id is not None):
            self.usage('cannot specify both --all and --name/--id simultaneously')
        if self.workflow_id is not None:
            if self.workflow_name is not None:
                self.usage('cannot specify both --id and --name simultaneously')
            validate_int(self.workflow_id, 'workflow id', 1)
            self.workflow_id = int(self.workflow_id)
        elif self.workflow_name is not None:
            validate_chars(self.workflow_name, 'workflow name', r'\w\s-')
        elif self._all:
            pass
        elif self.get_opt('list'):
            pass
        else:
            self.usage('must specify one of --name / --id / --all or use --list to find workflow names/IDs to specify')
        if self.max_age is not None:
            validate_float(self.max_age, 'max age', 1)
            self.max_age = float(self.max_age)
        if self.max_runtime is not None:
            validate_float(self.max_runtime, 'max runtime', 1)
            self.max_runtime = float(self.max_runtime)
        if self.min_runtime is not None:
            validate_float(self.min_runtime, 'min runtime', 0)
            self.min_runtime = float(self.min_runtime)
            if self.max_runtime is not None and self.min_runtime > self.max_runtime:
                self.usage('--min-runtime cannot be greater than --max-runtime!')

    def run(self):
        self.url_base = '{protocol}://{host}:{port}/bedrock-app/services/rest'.format(host=self.host, port=self.port,
                                                                                      protocol=self.protocol)
        # auth first, get JSESSIONID cookie
        # cookie jar doesn't work in Python or curl, must extract JSESSIONID to header manually
        #self.jar = cookielib.CookieJar()
        log.info('authenticating to Zaloni Bedrock')
        (_, self.auth_time) = self.req(url='{url_base}/admin/getUserRole'.format(url_base=self.url_base),
                                       # using json instead of constructing string manually,
                                       # this correctly escapes backslashes in password
                                       body=json.dumps({"username": self.user, "password": self.password}))
        # alternative method
        #session = requests.Session()
        #req = self.req(session,
        #               url='http://%(host)s:%(port)s/bedrock-app/services/rest/%(user)s/getUserRole' % locals(),
        #               method='POST')

        if self.get_opt('list'):
            self.list_workflows()

        if self._all:
            self.check_all_workflows()
        else:
            self.check_workflow(self.workflow_name, self.workflow_id)

    def check_all_workflows(self):
        workflows = self.get_workflows()
        if not workflows:
            qquit('UNKNOWN', 'no workflows found')
        results = {}
        try:
            for workflow in workflows:
                result = self.check_workflow(workflow['wfName'], None)
                if result is None:
                    results['No Runs'] = results.get('None', 0)
                    results['No Runs'] += 1
                    continue
                results[result] = results.get(result, 0)
                results[result] += 1
            self.msg = 'Zaloni workflows: '
            for result in results:
                self.msg += "'{0}' = {1}, ".format(result, results[result])
            self.msg = self.msg.rstrip(', ')
        except KeyError as _:
            qquit('UNKNOWN', 'parsing workflows for --all failed: {0}. '.format(_) + support_msg_api())

    # because timedelta.total_seconds() >= Python 2.7+
    @staticmethod
    def timedelta_seconds(timedelta_arg):
        return timedelta_arg.seconds + timedelta_arg.days * 24 * 3600

    @staticmethod
    def extract_response_message(response_dict):
        try:
            return'{0}: {1}. '.format(response_dict['status']['responseCode'],
                                      response_dict['status']['responseMessage'])
        except KeyError:
            log.warn('failed to extract responseCode/responseMessage for additional error information. ' \
                     + support_msg_api())
            return ''

    def check_workflow(self, workflow_name, workflow_id):
        log.info("checking workflow '%s' id '%s'", workflow_name, workflow_id)
        # GET /workflow/fetchWorkflowStatus/<instance_id> is also available but only uses wfId, doesn't support wfName
        # returns ['result']['list'] = [ {}, {}, ... ]
        (req, self.query_time) = self.req(url='{url_base}/workflow/publish/getWorkflowExecutionHistory'
                                          .format(url_base=self.url_base),
                                          # orders by newest first, but seems to return last 10 anyway
                                          body=json.dumps({'chunk_size': 1,
                                                           'currentPage': 1,
                                                           'wfName': workflow_name,
                                                           'wfId': workflow_id}))
        info = ''
        if workflow_name:
            info += " name '{0}'".format(workflow_name)
        if workflow_id:
            info += " id '{0}'".format(workflow_id)
        try:
            json_dict = json.loads(req.content)
            result = json_dict['result']
            not_found_err = '{0}. {1}'.format(info, self.extract_response_message(json_dict)) + \
                            'Perhaps you specified the wrong name/id or the workflow hasn\'t run yet? ' + \
                            'Use --list to see existing workflows'
            if result is None:
                if self._all:
                    return None
                qquit('CRITICAL', "no results found for workflow{0}".format(not_found_err))
            reports = result['jobExecutionReports']
            if not isList(reports):
                raise ValueError('jobExecutionReports is not a list')
            if not reports:
                qquit('CRITICAL', "no reports found for workflow{0}".format(not_found_err))
            # orders by newest first by default, checking last run only
            report = self.get_latest_complete_report(reports)
            status = report['status']
            if status == 'SUCCESS':
                pass
            elif status == 'INCOMPLETE':
                self.warning()
            else:
                self.critical()
            self.msg += "workflow '{workflow}' id '{id}' status = '{status}'".format(workflow=report['wfName'],
                                                                                     id=report['wfId'],
                                                                                     status=status)
            if not self._all:
                self.check_times(report['startDate'], report['endDate'])
            return status
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing workflow execution history: {0}'.format(_))

    @staticmethod
    def get_latest_complete_report(reports):
        if not isList(reports):
            code_error('non-list passed to get_lastest_complete_report()')
        if not reports:
            qquit('UNKNOWN', 'no reports passed to get_latest_complete_report()')
        num_reports = len(reports)
        index = 0
        report = reports[index]
        while report['status'] == 'INCOMPLETE':
            index += 1
            if index < num_reports:
                report = reports[index]
            else:
                log.warn('only incomplete workflows detected, will have to use latest incomplete workflow')
                report = reports[0]
        return report

    def check_times(self, start_date, end_date):
        start_date = str(start_date).strip()
        end_date = str(end_date).strip()
        invalid_dates = ('', 'null', 'None', None)
        age_timedelta = None
        runtime_delta = None
        if start_date not in invalid_dates and \
           end_date not in invalid_dates:
            try:
                start_datetime = datetime.strptime(start_date, '%m/%d/%Y %H:%M:%S')
                end_datetime = datetime.strptime(end_date, '%m/%d/%Y %H:%M:%S')
            except ValueError as _:
                qquit('UNKNOWN', 'error parsing date time format: {0}'.format(_))
            runtime_delta = end_datetime - start_datetime
            runtime_delta_secs = self.timedelta_seconds(runtime_delta)
            self.msg += ' in {0}'.format(sec2human(runtime_delta_secs))
            if self.max_runtime is not None and (runtime_delta_secs / 60.0) > self.max_runtime:
                self.warning()
                self.msg += ' (greater than {0} min{1}!)'.format(str(self.max_runtime).rstrip('0').rstrip('.'),
                                                                 plural(self.max_runtime))
            if self.min_runtime is not None and (runtime_delta_secs / 60.0) < self.min_runtime:
                self.warning()
                self.msg += ' (less than {0} min{1}!)'.format(str(self.min_runtime).rstrip('0').rstrip('.'),
                                                              plural(self.min_runtime))
            age_timedelta = datetime.now() - start_datetime
            age_timedelta_secs = self.timedelta_seconds(age_timedelta)
        if self.verbose:
            self.msg += ", start date = '{startdate}', end date = '{enddate}'".\
                        format(startdate=start_date, enddate=end_date)
            if age_timedelta is not None:
                self.msg += ', started {0} ago'.format(sec2human(age_timedelta_secs))
        if self.max_age is not None and age_timedelta is not None \
           and age_timedelta_secs > (self.max_age * 60.0):
            self.warning()
            self.msg += ' (last run started more than {0} min{1} ago!)'.format(str(self.max_age)
                                                                               .rstrip('0')
                                                                               .rstrip('.'),
                                                                               plural(self.max_age))
        # Do not output variable number of fields at all if agedelta is not available as that breaks PNP4Nagios graphing
        if age_timedelta is not None and runtime_delta:
            self.msg += ' |'
            self.msg += ' runtime={0}s;{1}'.format(runtime_delta_secs, self.max_runtime * 60 \
                                                                            if self.max_runtime else '')
            self.msg += ' age={0}s;{1}'.format(age_timedelta_secs, self.max_age * 60 if self.max_age else '')
            self.msg += ' auth_time={auth_time}s query_time={query_time}s'.format(auth_time=self.auth_time,
                                                                                  query_time=self.query_time)

    def get_workflows(self):
        log.info('listing workflows')
        (req, _) = self.req(url='{url_base}/workflow/getWorkFlows'.format(url_base=self.url_base),
                            # if you have more than 1M workflows in Zaloni you're probably bankrupt or
                            # have migrated to an open source tool already ;)
                            body=json.dumps({'chunk_size': 1000000, 'currentPage': 1, 'sortBy': 'wfName'}))
        try:
            json_dict = json.loads(req.content)
            workflows = json_dict['result']['workFlowDetails']
            if not isList(workflows):
                qquit('UNKNOWN', 'non-list returned for workFlowDetails.' + support_msg_api())
            return workflows
        except ValueError as _:
            qquit('UNKNOWN', 'failed to parse response from Zaloni Bedrock when requesting workflow list: {0}'\
                             .format(_))

    def list_workflows(self):
        workflows = self.get_workflows()
        print('Zaloni Bedrock Workflows:\n')
        if not workflows:
            print('<none>')
            sys.exit(ERRORS['UNKNOWN'])
        fields = {'wfName': 'Name',
                  'wfId': 'ID',
                  'category': 'Category',
                  'createdBy': 'Created By',
                  #'createdDate': 'Created Date',
                  'modifiedBy': 'Modified By',
                  #'modifiedDate': 'Modified Date'}
                 }
        widths = {}
        total_width = 0
        separator_width = 4
        for field in fields:
            widths[field] = len(fields[field]) + separator_width
        try:
            for workflow in workflows:
                for field in fields:
                    # pre-created by field headers above now
                    #widths[field] = widths.get(field, 0)
                    field_len = len(str(workflow[field]).strip()) + separator_width
                    if field_len > widths[field]:
                        widths[field] = field_len
            for field in widths:
                total_width += widths[field]
            print('=' * total_width)
            for field in ['wfName', 'wfId', 'category', 'createdBy', 'modifiedBy']:
                print('{0:<{1}}'.format(fields[field], widths[field]), end='')
            print()
            print('=' * total_width)
            for workflow in workflows:
                for field in fields:
                    print('{0:<{1}}'.format(workflow[field], widths[field]), end='')
                print()
            sys.exit(ERRORS['UNKNOWN'])
        except KeyError as _:
            qquit('UNKNOWN', 'failed to parse response from Zaloni Bedrock when requesting workflow list: {0}'\
                             .format(_))

    def req(self, url, method='post', body=None):
        if not isStr(method):
            code_error('non-string method passed to req()')
        log.debug('%s %s', method.upper(), url)
        headers = {"Content-Type": "application/json",
                   "Accept": "application/json",
                   "JSESSIONID": self.jsessionid}
        log.debug('headers: %s', headers)
        start_time = time.time()
        try:
            req = getattr(requests, method.lower())(url,
                                                    #cookies=self.jar,
                                                    data=body,
                                                    headers=headers)
            for cookie_tuple in req.cookies.items():
                if cookie_tuple[0] == 'JSESSIONID':
                    self.jsessionid = cookie_tuple[1].rstrip('/')
            timing = time.time() - start_time
        except requests.exceptions.RequestException as _:
            qquit('CRITICAL', _)
        if log.isEnabledFor(logging.DEBUG):
            log.debug("response: %s %s", req.status_code, req.reason)
            content = req.content
            try:
                content = jsonpp(req.content).strip()
            except ValueError:
                pass
            log.debug("content:\n%s\n%s\n%s", '='*80, content, '='*80)
        if req.status_code != 200:
            info = ''
            try:
                info = ': {0}'.format(json.loads(req.content)['result'])
            except (KeyError, ValueError):
                pass
            qquit('CRITICAL', "%s %s%s" % (req.status_code, req.reason, info))
        return (req, timing)


if __name__ == '__main__':
    CheckZaloniBedrockWorkflow().main()
