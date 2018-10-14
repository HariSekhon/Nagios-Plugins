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

Checks ingest history via a combination of:

1. Time - between now and M mins prior (defaults to 1440 mins for 24 hours)
2. N number of last ingestion runs
3. Source file/directory path
4. Destination file/directory path

Checks applied to each ingestion found:

1. status (SUCCESS is expected, INCOMPLETE skipped, use max run time to catch overrun / stalled incomplete ingestions)
2. max run time in mins for any currently incomplete ingestion runs (defaults to 1380 mins for 23 hours)
3. max age in mins since last ingestion run started to check ingestions are being triggering (optional)
4. perfdata for time since last ingestion and max incomplete ingestion run time, as well as auth & query timings

Verbose mode will output the ingestion start date/time of the last ingestion run

Use --list to see previous ingestions with their details you can use for filtering

Caveat: there is no API endpoint to list ingestions, so increase --num along with --list
to find more ingestions to filter on

Tested on Zaloni Bedrock 4.1.1 with Hortonworks HDP 2.4.2
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
#from __future__ import unicode_literals

from datetime import datetime, timedelta
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
    from harisekhon.utils import log, log_option, qquit
    #from harisekhon.utils import CriticalError, UnknownError
    from harisekhon.utils import validate_host, validate_port, validate_user, validate_password, \
                                 validate_int, validate_float, \
                                 jsonpp, isList, isDict, isStr, ERRORS, support_msg_api, code_error, \
                                 sec2human, plural, merge_dicts
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4.3'


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
        self.history_mins = 1440
        self.ok()

    def add_options(self):
        self.add_hostoption(name='Zaloni Bedrock', default_host='localhost', default_port=8080)
        self.add_useroption(name='Zaloni Bedrock', default_user='admin')
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL')
        self.add_opt('-T', '--history-mins', default=self.history_mins,
                     help='How far back to search ingestion history in minutes ' \
                        + '(default: 1440 ie. 24 hours, set to zero to disable time based search)')
        self.add_opt('-n', '--num', help='Number of previous ingestions to check (defaults to last 10 if a filter ' \
                                    + 'is given, 100 otherwise)')
        # ingestion IDs uniquely generated for every ingest so there is no point in checking an ingestion id
        #self.add_opt('-i', '--id', metavar='<int>',
        #             help='Ingestion ID filter (optional)')
        self.add_opt('-s', '--source', metavar='<URI>', help='Source file/directory location filter (optional)')
        self.add_opt('-d', '--dest', metavar='<URI>', help='Destination file/directory location filter (optional)')
        self.add_opt('-a', '--max-age', metavar='<mins>',
                     help='Max age in mins since start of last ingest (optional)')
        self.add_opt('-r', '--max-runtime', metavar='<mins>', default=1380,
                     help='Max runtime time in mins for any currently incomplete ingests ' +
                     '(default: 1380 ie. 23 hours)')
        self.add_opt('-l', '--list', action='store_true', help='List ingestions and exit')

    def run(self):
        self.no_args()
        host = self.get_opt('host')
        port = self.get_opt('port')
        user = self.get_opt('user')
        password = self.get_opt('password')
        if self.get_opt('ssl'):
            self.protocol = 'https'
        history_mins = self.get_opt('history_mins')
        num = self.get_opt('num')
        #inventory_id = self.get_opt('id')
        source = self.get_opt('source')
        dest = self.get_opt('dest')
        max_age = self.get_opt('max_age')
        max_runtime = self.get_opt('max_runtime')
        validate_host(host)
        validate_port(port)
        validate_user(user)
        validate_password(password)
        validate_float(history_mins, 'history mins')
        self.history_mins = float(history_mins)
        filter_opts = {}
        if self.history_mins:
            now = datetime.now()
            filter_opts['dateRangeStart'] = datetime.strftime(now - timedelta(minutes=self.history_mins), '%F %H:%M:%S')
            filter_opts['dateRangeEnd'] = datetime.strftime(now, '%F %H:%M:%S')
        if num is not None:
            validate_int(num, 'num ingestions', 1)
        #if inventory_id is not None:
        #    validate_chars(inventory_id, 'ingestion id', r'\w-')
        #    filter_opts['inventoryId'] = inventory_id
        if source is not None:
            log_option('source', source)
            filter_opts['fileName'] = source
        if dest is not None:
            log_option('dest', dest)
            filter_opts['destinationPath'] = dest
        if max_age is not None:
            validate_float(max_age, 'max age', 1)
            max_age = float(max_age)
        if max_runtime is not None:
            validate_float(max_runtime, 'max incomplete runtime', 1)
            max_runtime = float(max_runtime)

        self.url_base = '{protocol}://{host}:{port}/bedrock-app/services/rest'.format(host=host,
                                                                                      port=port,
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
            self.list_ingestions(num=num)

        self.check_ingestion(num=num, filter_opts=filter_opts, max_age=max_age, max_runtime=max_runtime)

    def check_ingestion(self, num, filter_opts=None, max_age=None, max_runtime=None):
        log.info('checking ingestion history')
        json_dict = self.get_ingestions(num, filter_opts)
        info = ''
        if self.verbose:
            for key in sorted(filter_opts):
                info += " {0}='{1}'".format(key, filter_opts[key])
        try:
            results = json_dict['result']
            if not results:
                qquit('CRITICAL', "no results found for ingestion{0}"\
                      .format('{0}. {1}'.format(info, self.extract_response_message(json_dict)) + \
                      'Perhaps you specified incorrect filters? Use --list to see existing ingestions'))
            num_results = len(results)
            log.info('%s ingestion history results returned', num_results)
            self.check_statuses(results)
            if num:
                self.msg += ' out of last {0} ingest{1}'.format(num_results, plural(num_results))
            if self.history_mins:
                self.msg += ' within last {0} ({1} min{2})'.format(sec2human(self.history_mins * 60),
                                                                   str(self.history_mins).rstrip('0').rstrip('.'),
                                                                   plural(self.history_mins))
            longest_incomplete_timedelta = self.check_longest_incomplete_ingest(results, max_runtime)
            age_timedelta_secs = self.check_last_ingest_age(results, max_age=max_age)
            self.msg_filter_details(filter_opts=filter_opts)
            self.msg += ' |'
            self.msg += ' last_ingest_age={0}s;{1}'.format(age_timedelta_secs,
                                                           max_age * 3600 if max_age else '')
            self.msg += ' longest_incomplete_ingest_age={0}s;{1}'\
                        .format(self.timedelta_seconds(longest_incomplete_timedelta)
                                if longest_incomplete_timedelta else 0,
                                max_age * 3600 if max_age else '')
            self.msg += ' auth_time={auth_time}s query_time={query_time}s'.format(auth_time=self.auth_time,
                                                                                  query_time=self.query_time)
        except KeyError as _:
            qquit('UNKNOWN', 'error parsing workflow execution history: {0}'.format(_))

    def msg_filter_details(self, filter_opts):
        params_reference = [('inventoryId', 'id'), ('fileName', 'source'), ('destinationPath', 'dest')]
        if self.verbose and [param for (param, _) in params_reference if param in filter_opts]:
            self.msg += ' for'
            for (param, name) in params_reference:
                if param in filter_opts:
                    self.msg += " {name}='{value}'".format(name=name, value=filter_opts[param])

    def check_statuses(self, results):
        # known statuses from doc: SUCCESS / INGESTION FAILED / WORKFLOW FAILED / INCOMPLETE
        log.info('checking statuses')
        result_statuses = {}
        num_results = len(results)
        for item in results:
            status = item['status']
            result_statuses[status] = result_statuses.get(status, 0)
            result_statuses[status] += 1
        if not result_statuses:
            code_error('no ingestion status results parsed')
        if 'SUCCESS' not in result_statuses:
            self.msg += 'NO SUCCESSFUL INGESTS in history of last {0} ingest runs! '.format(num_results)
            self.warning()
        self.msg += 'ingestion{0} status: '.format(plural(num_results))
        for status in result_statuses:
            if status not in ('SUCCESS', 'INCOMPLETE'):
                self.critical()
            self.msg += '{0} = {1} time{2}, '.format(status, result_statuses[status],
                                                     plural(result_statuses[status]))
        self.msg = self.msg.rstrip(', ')
        return result_statuses

    def check_longest_incomplete_ingest(self, result, max_runtime=None):
        log.info('checking longest running incomplete ingest')
        longest_incomplete_timedelta = None
        for item in result:
            status = item['status']
            if status == 'INCOMPLETE' and max_runtime is not None:
                runtime_delta = self.get_timedelta(item['ingestionTimeFormatted'])
                if longest_incomplete_timedelta is None or \
                   self.timedelta_seconds(runtime_delta) > self.timedelta_seconds(longest_incomplete_timedelta):
                    longest_incomplete_timedelta = runtime_delta
        if max_runtime is not None and \
           longest_incomplete_timedelta is not None and \
           self.timedelta(longest_incomplete_timedelta) > max_runtime * 60.0:
            self.warning()
            self.msg += ', longest incomplete ingest runtime = {0} ago! '\
                        .format(sec2human(self.timedelta_seconds(longest_incomplete_timedelta))) + \
                        '(greater than expected {0} min{1})'\
                        .format(str(max_runtime).rstrip('0').rstrip('.'), plural(max_runtime))
        return longest_incomplete_timedelta

    def check_last_ingest_age(self, results, max_age):
        log.info('checking last ingest age')
        if not isList(results):
            code_error('passed non-list to check_last_ingest_age()')
        # newest is first
        # effectiveDate is null in testing (docs says it's a placeholder for future use)
        # using ingestionTimeFormatted instead, could also use ingestionTime which is timestamp in millis
        ingestion_date = results[0]['ingestionTimeFormatted']
        age_timedelta = self.get_timedelta(ingestion_date=ingestion_date)
        age_timedelta_secs = self.timedelta_seconds(age_timedelta)
        if self.verbose:
            self.msg += ", last ingest start date = '{ingestion_date}'".format(ingestion_date=ingestion_date)
            self.msg += ', started {0} ago'.format(sec2human(age_timedelta_secs))
        if max_age is not None and age_timedelta_secs > (max_age * 60.0):
            self.warning()
            self.msg += ' (last run started more than {0} min{1} ago!)'.format(str(max_age)
                                                                               .rstrip('0')
                                                                               .rstrip('.'),
                                                                               plural(max_age))
        return age_timedelta_secs

    @staticmethod
    def extract_response_message(response_dict):
        try:
            status = response_dict['status']['responseCode']
            if status != 200:
                return'{0}: {1}. '.format(response_dict['status']['responseCode'],
                                          response_dict['status']['responseMessage'])
            return ''
        except KeyError:
            log.warn('failed to extract responseCode/responseMessage for additional error information. ' +
                     support_msg_api())
            return ''

    def get_ingestions(self, num=None, filter_opts=None):
        log.info('getting ingestion history')
        if num:
            chunk_size = num
            log.info('explicit number of results requested: %s', chunk_size)
        elif filter_opts:
            chunk_size = 10
            log.info('filters detected, defaulting number of results to %s', chunk_size)
        else:
            chunk_size = 100
            log.info('using catch all default result limit of %s', chunk_size)
        settings = {'chunkSize': chunk_size, 'currentPage': 1}
        if filter_opts is not None:
            if not isDict(filter_opts):
                code_error('passed non-dictionary for filter opts to get_ingestions')
            for key, value in sorted(filter_opts.items()):
                log.info("filter: '%s' = '%s'", key, value)
            settings = merge_dicts(settings, filter_opts)
        log.info('settings: %s', settings)
        log.info('querying Zaloni for ingestion history')
        (req, self.query_time) = self.req(url='{url_base}/ingestion/publish/getFileIndex'
                                          .format(url_base=self.url_base),
                                          # orders by newest first, but seems to return last 10 anyway
                                          body=json.dumps(settings))
        try:
            log.info('parsing JSON response')
            json_dict = json.loads(req.content)
        except ValueError as _:
            qquit('UNKNOWN', 'error parsing json returned by Zaloni: {0}'.format(_))
        return json_dict

    @staticmethod
    def get_timedelta(ingestion_date):
        ingestion_date = str(ingestion_date).strip()
        invalid_ingestion_dates = ('', 'null', 'None', None)
        if ingestion_date not in invalid_ingestion_dates:
            try:
                # parsing the date will break notifying us if the API format changes in future
                # whereas if millis changes to secs or similar we could be way off
                ingestion_datetime = datetime.strptime(ingestion_date, '%Y-%m-%d %H:%M:%S.%f')
            except ValueError as _:
                qquit('UNKNOWN', 'error parsing ingestion date time format: {0}'.format(_))
        time_delta = datetime.now() - ingestion_datetime
        return time_delta

    # because timedelta.total_seconds() >= Python 2.7+
    @staticmethod
    def timedelta_seconds(timedelta_arg):
        return timedelta_arg.seconds + timedelta_arg.days * 24 * 3600

    def list_ingestions(self, num=None):
        log.info('listing ingestions')
        json_dict = self.get_ingestions(num)
        try:
            result = json_dict['result']
            if not result:
                print('<none>')
                sys.exit(ERRORS['UNKNOWN'])
            if not isList(result):
                qquit('UNKNOWN', 'non-list returned for workFlowDetails.' + support_msg_api())
            log.info('%s ingestion history results returned', len(result))
            fields = {\
                      'destFile': 'Destination Path',
                      'entity': 'Entity',
                      'ingestionTimeFormatted': 'Ingestion Start Time',
                      'sourceFile': 'Source Path',
                      'sourcePlatform': 'Source Platform',
                      'sourceSchema': 'Source Schema',
                      'targetTable': 'Target Table',
                      'wfInstanceId': 'Workflow Instance ID',
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
                for field in sorted(fields):
                    print('{0}: {1}'.format(fields[field], item[field]))
                print()
            sys.exit(ERRORS['UNKNOWN'])
        except (KeyError, ValueError) as _:
            qquit('UNKNOWN', 'failed to parse response from Zaloni Bedrock when requesting ingestion list: {0}'\
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
    CheckZaloniBedrockIngestion().main()
