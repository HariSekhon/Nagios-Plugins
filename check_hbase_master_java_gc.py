#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-08-17 18:59:54 +0100 (Fri, 17 Aug 2018)
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

Nagios Plugin to check HBase Master Java GC last duration via JMX API

Thresholds apply to Java Garbage Collection last duration in seconds

Tested on Apache HBase 0.95, 0.96, 0.98, 1.0, 1.1, 1.2, 1.3, 1.4, 2.0, 2.1

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import sys
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from check_hadoop_namenode_java_gc import CheckHadoopNameNodeJavaGC
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.1'


class CheckHBaseMasterJavaGC(CheckHadoopNameNodeJavaGC):

    def __init__(self):
        # Python 2.x
        super(CheckHBaseMasterJavaGC, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = ['HBase Master', 'HBase']
        self.default_port = 16010

    def add_options(self):
        # This is what I meant to do pylint, set the default thresholds lower
        super(CheckHadoopNameNodeJavaGC, self).add_options()  # pylint: disable=bad-super-call
        self.add_thresholds(default_warning=2, default_critical=10)


if __name__ == '__main__':
    CheckHBaseMasterJavaGC().main()
