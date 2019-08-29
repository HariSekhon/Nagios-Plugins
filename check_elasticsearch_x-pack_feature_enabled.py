#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2018-03-05 19:09:03 +0000 (Mon, 05 Mar 2018)
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

Nagios Plugin to check a given Elasticsearch X-Pack feature is enabled via the X-Pack API

Useful for checking that X-Pack Security and Monitoring are enabled

Tested on Elasticsearch with X-Pack 6.0, 6.1, 6.2

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
    from harisekhon import RestNagiosPlugin
    from harisekhon.utils import ERRORS, validate_alnum
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.2'


class CheckElasticsearchXPackFeatureEnabled(RestNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckElasticsearchXPackFeatureEnabled, self).__init__()
        # Python 3.x
        # super().__init__()
        self.name = 'Elasticsearch'
        self.default_port = 9200
        #self.path = '/_xpack?categories=license,features'
        self.path = '/_xpack?categories=features&human=false'
        self.auth = 'optional'
        self.json = True
        self.msg = 'Elasticsearch msg not defined yet'
        self.feature = None

    def add_options(self):
        super(CheckElasticsearchXPackFeatureEnabled, self).add_options()
        self.add_opt('-f', '--feature', help='Feature to check is enabled (case sensitive, eg. security, monitoring)')
        self.add_opt('-l', '--list-features', action='store_true', help='List features and exit')

    def process_options(self):
        super(CheckElasticsearchXPackFeatureEnabled, self).process_options()
        self.feature = self.get_opt('feature')
        if not self.get_opt('list_features'):
            validate_alnum(self.feature, 'feature')

    @staticmethod
    def list_features(features):
        print('Elasticsearch X-Pack Features:\n')
        width = 0
        for feature in features:
            if len(feature) > width:
                width = len(feature)
        print('=' * 40)
        print('{0:<{1}}\t{2}\t{3}'.format('Feature', width, 'Available', 'Enabled'))
        print('=' * 40)
        for feature in sorted(features):
            print('{0:<{1}s}\t{2:<9}\t{3}'.format(feature,
                                                  width,
                                                  str(features[feature]['available']),
                                                  features[feature]['enabled']))
        sys.exit(ERRORS['UNKNOWN'])

    def parse_json(self, json_data):
        features = json_data['features']
        if self.get_opt('list_features'):
            self.list_features(features)
        self.msg = "Elasticsearch X-Pack feature '{}' ".format(self.feature)
        if self.feature in features:
            available = features[self.feature]['available']
            enabled = features[self.feature]['enabled']
            self.msg += 'available = {}, enabled = {}'.format(available, enabled)
            if not (available and enabled):
                self.critical()
        else:
            self.critical()
            self.msg += " not found!"


if __name__ == '__main__':
    CheckElasticsearchXPackFeatureEnabled().main()
