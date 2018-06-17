#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#
#  Author: Hari Sekhon
#  Date: 2017-08-30 14:52:43 +0200 (Wed, 30 Aug 2017)
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

Nagios Plugin to check a docker image has been pulled with optional checks for checksum and size via the Docker API

Optional --warning / --critical thresholds apply to the virtual size of the docker image

Optional --id applies to the expected checksum id of the docker image to expect

"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import logging
import os
import re
import sys
import traceback
try:
    import docker
    import humanize
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, jsonpp, CriticalError, UnknownError, support_msg_api
    from harisekhon.utils import validate_chars
    from harisekhon import DockerNagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.6.0'


class CheckDockerImage(DockerNagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerImage, self).__init__()
        # Python 3.x
        # super().__init__()
        self.msg = 'Docker msg not defined'
        self.docker_image = None
        self.expected_id = None

    def add_options(self):
        super(CheckDockerImage, self).add_options()
        self.add_opt('-d', '--docker-image', help='Docker image, in form of <repository>:<tag>')
        self.add_opt('-i', '--id', help='Docker image ID to expect docker image to have')
        self.add_thresholds()

    def process_options(self):
        super(CheckDockerImage, self).process_options()
        self.docker_image = self.get_opt('docker_image')
        validate_chars(self.docker_image, 'docker image', r'A-Za-z0-9/:\.-')
        self.expected_id = self.get_opt('id')
        if self.expected_id is not None:
            validate_chars(self.expected_id, 'expected id', 'A-Za-z0-9:-')
        self.validate_thresholds(optional=True)

    def check(self, client):
        # images = client.images.list()
        # print(images)
        try:
            image = client.images.get(self.docker_image)
        except docker.errors.APIError as _:
            raise CriticalError(_)
        if log.isEnabledFor(logging.DEBUG):
            log.debug(jsonpp(image.attrs))

        _id = image.short_id
        #size = image.attrs['Size']
        size = image.attrs['VirtualSize']

        self.msg = "Docker image '{repo}'".format(repo=self.docker_image)
        self.check_id(_id)
        self.check_size(size)

    def check_id(self, _id):
        log.debug('id: %s', _id)
        self.msg += ", id = '{id}'".format(id=_id)
        if self.expected_id:
            log.debug('checking expected --id')
            if not re.match(r'(sha\d+:)?\w+', _id):
                raise UnknownError("{msg} not in sha format as expected! {support}"\
                                   .format(msg=self.msg, support=support_msg_api()))
            if _id != self.expected_id:
                self.critical()
                self.msg += " (expected id = '{0}')".format(self.expected_id)

    def check_size(self, size):
        human_size = humanize.naturalsize(size)
        self.msg += ", size = {human_size}".format(human_size=human_size)
        log.debug('checking size %s against thresholds', size)
        self.check_thresholds(size)
        self.msg += ' | size={}b{}'.format(size, self.get_perf_thresholds())


if __name__ == '__main__':
    CheckDockerImage().main()
