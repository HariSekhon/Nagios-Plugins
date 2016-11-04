#!/usr/bin/env python
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2016-11-04 14:30:30 +0000 (Fri, 04 Nov 2016)
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

Nagios Plugin to check Zaloni Bedrock ingestion via the REST API

Operates in one of two modes:

1. Checks the most recent N number of ingestions
2. Checks a specific ingestion ID for it's last or N most recent ingestions

Checks:

1. status
2. outputs ingestion date if specifying ID (optional)
3. age since last ingestion run in mins (optional)
4. perfdata for ingestion age if specifying ID (optional)

Can also list previous ingestions with IDs, workflow ID, sourceFile, destFile, triggerFile, target table
for easy reference

Verbose mode will output the effective date & time of the last ingestion if specifying --id and --num=1

Caveat: there is no API endpoint to list ingestions, so increasing --num will find more ingestion IDs

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
__version__ = '0.1'


class CheckZaloniBedrockIngestion(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckZaloniBedrockIngestion, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Zaloni '
        self.protocol = 'http'
        self.url_base = None
        #self.jar = None
        self.jsessionid = None
        self.auth_time = None
        self.query_time = None
        self.ok()

    def add_options(self):
        self.add_hostoption(name='Zaloni Bedrock', default_host='localhost', default_port=8080)
        self.add_useroption(name='Zaloni Bedrock', default_user='admin')
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-i', '--id', metavar='<int>',
                     help='Ingestion ID to check (see --list or UI to find these)')
        self.add_opt('-n', '--num', help='Number of previous ingestions to check (defaults to last 1 if ID is given, ' \
                                       + '100 if checking random ingests and 100,000 if listing ingests)')
        self.add_opt('-a', '--max-age', metavar='<mins>',
                     help='Ingestion max age, time in minutes since start of last ingest run (optional)')
        self.add_opt('-l', '--list', action='store_true',
                     help='List ingestions and exit (increase --num to find more ingestions as ' \
                        + 'there is no ingestion listing in the API)')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        user = self.get_opt('user')
        password = self.get_opt('password')
        ingestion_id = self.get_opt('id')
        num = self.get_opt('num')
        max_age = self.get_opt('max_age')
        if self.get_opt('ssl'):
            self.protocol = 'https'
        validate_host(host)
        validate_port(port)
        validate_user(user)
        validate_password(password)
        if num is not None:
            validate_int(num, 'num ingestions', 1)
            num = int(num)
        if ingestion_id is not None:
            validate_chars(ingestion_id, 'ingestion id', r'\w-')
        if max_age is not None:
            validate_float(max_age, 'max age', 1)
            max_age = float(max_age)

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
        if self.get_opt('list'):
            self.list_ingestions()

        self.check_ingestion(num=num, ingestion_id=ingestion_id, max_age=max_age)

    @staticmethod
    def extract_response_message(response_dict):
        try:
            status = response_dict['status']['responseCode']
            if status != 200:
                return'{0}: {1}. '.format(response_dict['status']['responseCode'],
                                          response_dict['status']['responseMessage'])
            else:
                return ''
        except KeyError:
            log.warn('failed to extract responseCode/responseMessage for additional error information. ' +
                     support_msg_api())
            return ''

    def get_ingestions(self, num, ingestion_id=None):
        if ingestion_id:
            log.info("checking ingestion id '%s'", ingestion_id)
        if num:
            chunk_size = num
        elif ingestion_id:
            chunk_size = 1
        elif self.get_opt('list'):
            # high to find as many previous ingestions as possible
            chunk_size = 100000
        else:
            chunk_size = 100
        (req, self.query_time) = self.req(url='{url_base}/ingestion/publish/getFileIndex'
                                          .format(url_base=self.url_base),
                                          # orders by newest first, but seems to return last 10 anyway
                                          body=json.dumps({'chunk_size': chunk_size,
                                                           'currentPage': 1,
                                                           'inventoryId': ingestion_id}))
        try:
            json_dict = json.loads(req.content)
        except ValueError as _:
            qquit('UNKNOWN', 'error parsing json returned by Zaloni: {0}'.format(_))
        return json_dict

    def check_ingestion(self, num, ingestion_id=None, max_age=None):
        log.info('checking ingestion history')
        json_dict = self.get_ingestions(num, ingestion_id)
        info = ''
        if ingestion_id:
            info += " id '{0}'".format(ingestion_id)
        try:
            result = json_dict['result']
            not_found_err = '{0}. {1}'.format(info, self.extract_response_message(json_dict)) + \
                            'Perhaps you specified the wrong --id? Use --list to see existing ingestions'
            if not result:
                qquit('CRITICAL', "no results found for ingestion{0}".format(not_found_err))
            #reports = result['jobExecutionReports']
            #if not isList(reports):
                #raise ValueError('jobExecutionReports is not a list')
            #if not reports:
            #    qquit('CRITICAL', "no reports found for workflow{0}".format(not_found_err))
            # orders by newest first by default, checking last run only
            log.info('%s ingestion history results returned', len(result))
            self.msg += 'ingestion'
            result_statuses = {}
            if num == 1:
                item = result[0]
                status = item['status']
                if status != 'SUCCESS':
                    self.critical()
                self.msg += "status = '{status}'".format(status=status)
                # effectiveDate is usually null in testing, while ingestionTimeFormatted is usually populated
                self.check_time(item['ingestionTimeFormatted'], max_age)
                if ingestion_id:
                    self.msg += " for id '{id}'".format(id=ingestion_id)
                self.msg += ' |'
                self.add_query_perfdata()
            else:
                self.msg += 's status: '
                for item in result:
                    status = item['status']
                    result_statuses[status] = result_statuses.get(status, 0)
                    result_statuses[status] += 1
                for status in result_statuses:
                    if status != 'SUCCESS':
                        self.critical()
                    self.msg += '{0} = {1} ingest{2}, '.format(status, result_statuses[status],
                                                               plural(result_statuses[status]))
                self.msg = self.msg.rstrip(', ')
                if ingestion_id:
                    self.msg += " for id '{id}'".format(id=ingestion_id)
                self.msg += ' |'
                self.add_query_perfdata()
        except KeyError as _:
            qquit('UNKNOWN', 'error parsing workflow execution history: {0}'.format(_))

    def check_time(self, ingestion_date, max_age):
        ingestion_date = str(ingestion_date).strip()
        invalid_ingestion_dates = ('', 'null', 'None', None)
        if ingestion_date not in invalid_ingestion_dates:
            try:
                ingestion_datetime = datetime.strptime(ingestion_date, '%m/%d/%Y %H:%M:%S')
            except ValueError as _:
                qquit('UNKNOWN', 'error parsing ingestion date time format: {0}'.format(_))
        age_timedelta = datetime.now() - ingestion_datetime
        if self.verbose:
            self.msg += ", ingestion date = '{ingestion_date}'".format(ingestion_date=ingestion_date)
            self.msg += ', started {0} ago'.format(sec2human(age_timedelta.seconds))
        if max_age is not None and age_timedelta.seconds > (max_age * 60.0):
            self.warning()
            self.msg += ' (last run started more than {0} min{1} ago!)'.format('{0}'.format(max_age).rstrip('.0'),
                                                                               plural(max_age))
        self.msg += ' |'
        self.msg += ' age={0}s;{1}'.format(age_timedelta.seconds, max_age * 3600 if max_age else '')
        self.add_query_perfdata()

    def add_query_perfdata(self):
        self.msg += ' auth_time={auth_time}s query_time={query_time}s'.format(auth_time=self.auth_time,
                                                                              query_time=self.query_time)

    def list_ingestions(self):
        log.info('listing ingestions')
        json_dict = self.get_ingestions(100000)
        try:
            result = json_dict['result']
            if not result:
                print('<none>')
                sys.exit(ERRORS['UNKNOWN'])
            if not isList(result):
                qquit('UNKNOWN', 'non-list returned for workFlowDetails.' + support_msg_api())
            log.info('%s ingestion history results returned', len(result))
            fields = {'entity': 'Entity',
                      'sourcePlatform': 'Source Platform',
                      'sourceFile': 'Source File',
                      'destFile': 'Dest File',
                     }
            ingestions = {}
            for item in result:
                _id = item['id']
                item_dict = {}
                if _id in ingestions:
                    continue
                for field in fields:
                    item_dict[field] = item[field]
                ingestions[_id] = item_dict
            log.info('%s unique ingestions found', len(ingestions))
            print('Zaloni Bedrock Ingestions:\n')
            for _id in sorted(ingestions):
                print('ID: {0}'.format(_id))
                item = ingestions[_id]
                for field in fields:
                    print('{0}: {1}'.format(fields[field], item[field]))
                print()
            sys.exit(ERRORS['UNKNOWN'])
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'failed to parse response from Zaloni Bedrock when requesting ingestion list: {0}'\
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
    CheckZaloniBedrockIngestion().main()
