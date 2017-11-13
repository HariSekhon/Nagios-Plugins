#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-06 14:25:26 +0200 (Wed, 06 Sep 2017)
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

Nagios Plugin to check a given Hadoop NameNode for failed NameDirs via NameNode JMX

Tested on HDP 2.6.1 and Apache Hadoop 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import json
import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, plural
    from harisekhon.utils import UnknownError, support_msg_api
    from harisekhon import RestNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.4'


# pylint: disable=too-few-public-methods
class CheckHadoopFailedNameDirs(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopFailedNameDirs, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['Hadoop NameNode', 'Hadoop']
        self.path = '/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo'
        self.default_port = 50070
        self.json = True
        self.auth = False
        self.msg = 'Message Not Defined'

    def parse_json(self, json_data):
        log.info('parsing response')
        try:
            data = json_data['beans'][0]
            name_dir_statuses = data['NameDirStatuses']
            name_dir_data = json.loads(name_dir_statuses)
            active_dirs = name_dir_data['active']
            failed_dirs = name_dir_data['failed']
            num_active_dirs = len(active_dirs)
            num_failed_dirs = len(failed_dirs)
            self.msg = 'NameNode has {0} failed dir{1}'.format(num_failed_dirs, plural(num_failed_dirs))
            if num_failed_dirs > 0:
                self.warning()
                if self.verbose:
                    self.msg += ' ({0})'.format(', '.join(failed_dirs))
            self.msg += ', {0} active dir{1}'.format(num_active_dirs, plural(num_active_dirs))
            if num_active_dirs < 1:
                self.critical()
            if self.verbose and num_active_dirs > 0:
                self.msg += ' ({0})'.format(', '.join(active_dirs))
            self.msg += ' | num_failed_dirs={0} num_active_dirs={1}'.format(num_failed_dirs, num_active_dirs)
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned for NameDirStatuses by Namenode '{0}:{1}': {2}"\
                               .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopFailedNameDirs().main()
