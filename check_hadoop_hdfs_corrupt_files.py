#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-09-06 16:33:17 +0200 (Wed, 06 Sep 2017)
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

Nagios Plugin to check for corrupt HDFS files via NameNode JMX

Outputs the number of corrupt files.

Use double verbose mode -vv to output the file list

Tested on HDP 2.6.1 and Apache Hadoop 2.3, 2.4, 2.5, 2.6, 2.7, 2.8

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
__version__ = '0.1'


# pylint: disable=too-few-public-methods
class CheckHadoopHDFSCorruptFiles(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckHadoopHDFSCorruptFiles, self).__init__()
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
            corrupt_files = data['CorruptFiles']
            corrupt_files_data = json.loads(corrupt_files)
            num_corrupt_files = len(corrupt_files_data)
            for filename in corrupt_files_data:
                log.info('corrupt file: %s', filename)
            self.msg = 'HDFS has {0} corrupt file{1}'.format(num_corrupt_files, plural(num_corrupt_files))
            if num_corrupt_files > 0:
                self.critical()
            self.msg += ' | hdfs_corrupt_files={0}'.format(num_corrupt_files)
        except KeyError as _:
            raise UnknownError("failed to parse json returned by NameNode at '{0}:{1}': {2}. {3}"\
                               .format(self.host, self.port, _, support_msg_api()))
        except ValueError as _:
            raise UnknownError("invalid json returned for CorruptFiles by Namenode '{0}:{1}': {2}"\
                               .format(self.host, self.port, _))


if __name__ == '__main__':
    CheckHadoopHDFSCorruptFiles().main()
