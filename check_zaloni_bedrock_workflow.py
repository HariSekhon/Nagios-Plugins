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

Can also list all workflows with names, IDs, category, owner and modified by for easy reference

Verbose mode will output the start/end date & time of the last job as well

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
                                 jsonpp, isList, isStr, ERRORS, support_msg_api, sec2human, plural
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3.1'


class CheckZaloniBedrockWorkflow(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckZaloniBedrockWorkflow, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Zaloni '
        self.protocol = 'http'
        self.url_base = None
        #self.jar = None
        self.jsessionid = None
        self.auth_time = None
        self.query_time = None

    def add_options(self):
        self.add_hostoption(name='Zaloni Bedrock', default_host='localhost', default_port=8080)
        self.add_useroption(name='Zaloni Bedrock', default_user='admin')
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-i', '--id', metavar='<int>',
                     help='Workflow ID to check (see --list or UI to find these)')
        self.add_opt('-n', '--name', metavar='<name>',
                     help='Workflow Name to check (see --list or UI to find these)')
        self.add_opt('-a', '--max-age', metavar='<mins>',
                     help='Workflow max age, time in minutes since start of last workflow run (optional)')
        self.add_opt('-r', '--max-runtime', metavar='<mins>',
                     help='Workflow max run time of last run in mins (optional)')
        self.add_opt('-l', '--list', action='store_true', help='List workflows and exit')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        user = self.get_opt('user')
        password = self.get_opt('password')
        workflow_id = self.get_opt('id')
        workflow_name = self.get_opt('name')
        max_age = self.get_opt('max_age')
        max_runtime = self.get_opt('max_runtime')
        if self.get_opt('ssl'):
            self.protocol = 'https'
        validate_host(host)
        validate_port(port)
        validate_user(user)
        validate_password(password)
        if workflow_id is not None:
            if workflow_name is not None:
                self.usage('cannot specify both --id and --name simultaneously')
            validate_int(workflow_id, 'workflow id', 1)
        elif workflow_name is not None:
            validate_chars(workflow_name, 'workflow name', r'\w-')
        elif self.get_opt('list'):
            pass
        else:
            self.usage('must specify either --name or --id or use --list to find them')
        if max_age is not None:
            validate_float(max_age, 'max age', 1)
            max_age = float(max_age)
        if max_runtime is not None:
            validate_float(max_runtime, 'max runtime', 1)
            max_runtime = float(max_runtime)

        self.url_base = '{protocol}://{host}:{port}/bedrock-app/services/rest'.format(host=host, port=port,
                                                                                      protocol=self.protocol)
        # auth first, get JSESSIONID cookie
        # cookie jar doesn't work in Python or curl, must extract JSESSIONID to header manually
        #self.jar = cookielib.CookieJar()
        log.info('authenticating to Zaloni Bedrock')
        (_, self.auth_time) = self.req(url='{url_base}/admin/getUserRole'.format(url_base=self.url_base),
                                       # using json instead of constructing string manually,
                                       # this correctly escapes backslashes in password
                                       body=json.dumps({"username": user, "password": password}))
        # alternative method
        #session = requests.Session()
        #req = self.req(session,
        #               url='http://%(host)s:%(port)s/bedrock-app/services/rest/%(user)s/getUserRole' % locals(),
        #               method='POST')

        if self.get_opt('list'):
            self.list_workflows()

        self.check_workflow(workflow_name, workflow_id, max_age, max_runtime)

    @staticmethod
    def extract_response_message(response_dict):
        try:
            return'{0}: {1}. '.format(response_dict['status']['responseCode'],
                                      response_dict['status']['responseMessage'])
        except KeyError:
            log.warn('failed to extract responseCode/responseMessage for additional error information. ' + support_msg_api())
            return ''

    def check_workflow(self, workflow_name, workflow_id, max_age=None, max_runtime=None):
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
                            'Perhaps you specified the wrong name/id? Use --list to see existing workflows'
            if result is None:
                qquit('CRITICAL', "no results found for workflow{0}".format(not_found_err))
            reports = result['jobExecutionReports']
            if not isList(reports):
                raise ValueError('jobExecutionReports is not a list')
            if not reports:
                qquit('CRITICAL', "no reports found for workflow{0}".format(not_found_err))
            # orders by newest first by default, checking last run only
            report = reports[0]
            status = report['status']
            if status == 'SUCCESS':
                self.ok()
            else:
                self.critical()
            self.msg += "workflow '{workflow}' id '{id}' status = '{status}'".format(workflow=report['wfName'],
                                                                                     id=report['wfId'],
                                                                                     status=status)
            self.check_times(report['startDate'], report['endDate'], max_age, max_runtime)
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'error parsing workflow execution history: {0}'.format(_))

    def check_times(self, start_date, end_date, max_age, max_runtime):
        try:
            start_datetime = datetime.strptime(start_date, '%m/%d/%Y %H:%M:%S')
            end_datetime = datetime.strptime(end_date, '%m/%d/%Y %H:%M:%S')
        except ValueError as _:
            qquit('UNKNOWN', 'error parsing date time format: {0}'.format(_))
        runtime_delta = end_datetime - start_datetime
        self.msg += ' in {0}'.format(sec2human(runtime_delta.seconds))
        if max_runtime is not None and max_runtime > (runtime_delta.seconds / 3600.0):
            self.warning()
            self.msg += ' (greater than {0} min{1}!)'.format('{0}'.format(max_runtime).rstrip('.0'),
                                                             plural(max_runtime))
        age_timedelta = datetime.now() - start_datetime
        if self.verbose:
            self.msg += ", start date = '{startdate}', end date = '{enddate}'".\
                        format(startdate=start_date, enddate=end_date)
            self.msg += ', started {0} ago'.format(sec2human(age_timedelta.seconds))
        if max_age is not None and age_timedelta.seconds > (max_age * 60.0):
            self.warning()
            self.msg += ' (last run started more than {0} min{1} ago!)'.format('{0}'.format(max_age).rstrip('.0'),
                                                                               plural(max_age))
        self.msg += ' |'
        self.msg += ' runtime={0}s;{1}'.format(runtime_delta.seconds, max_runtime * 3600 if max_runtime else '')
        self.msg += ' age={0}s;{1}'.format(age_timedelta.seconds, max_age * 3600 if max_age else '')
        self.msg += ' auth_time={auth_time}s query_time={query_time}s'.format(auth_time=self.auth_time,
                                                                              query_time=self.query_time)

    def list_workflows(self):
        log.info('listing workflows')
        (req, _) = self.req(url='{url_base}/workflow/getWorkFlows'.format(url_base=self.url_base),
                            # if you have more than 1M workflows in Zaloni you're probably bankrupt or
                            # have migrated to an open source tool already ;)
                            body=json.dumps({'chunk_size': 1000000, 'currentPage': 1, 'sortBy': 'wfName'}))
        try:
            json_dict = json.loads(req.content)
            workflows = json_dict['result']['workFlowDetails']
            print('Zaloni Bedrock Workflows:\n')
            if workflows is None or not workflows:
                print('<none>')
                sys.exit(ERRORS['UNKNOWN'])
            if not isList(workflows):
                qquit('UNKNOWN', 'non-list returned for workFlowDetails.' + support_msg_api())
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
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'failed to parse response from Zaloni Bedrock when requesting workflow list: {0}'\
                             .format(_))

    def req(self, url, method='post', body=None):
        assert isStr(method)
        log.debug('%s %s', method.upper(), url)
        headers = {"Content-Type": "application/json",
                   "Accept": "application/json",
                   "JSESSIONID": self.jsessionid}
        log.debug('headers: %s', headers)
        start_time = time.time()
        try:
            req = getattr(requests, method)(url,
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
