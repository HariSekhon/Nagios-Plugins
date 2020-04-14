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

Nagios Plugin to check a local docker image has been pulled with optional checks for checksum and size

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
import subprocess
import traceback
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon.utils import log, CriticalError, UnknownError, support_msg
    from harisekhon.utils import expand_units, which, validate_chars, isPythonMinVersion
    from harisekhon import NagiosPlugin
except ImportError as _:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.5.3'


class CheckDockerImage(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckDockerImage, self).__init__()
        # Python 3.x
        # super().__init__()
        self.ok()
        self.msg = 'docker msg not defined'
        self.docker_image = None
        self.expected_id = None

    def add_options(self):
        self.add_opt('-d', '--docker-image', help='Docker image, in form of <repository>:<tag>')
        self.add_opt('-i', '--id', help='Docker image ID to expect docker image to have')
        self.add_thresholds()

    def process_options(self):
        self.no_args()
        self.docker_image = self.get_opt('docker_image')
        validate_chars(self.docker_image, 'docker image', 'A-Za-z0-9/:-')
        self.expected_id = self.get_opt('id')
        if self.expected_id is not None:
            validate_chars(self.expected_id, 'expected id', 'A-Za-z0-9:-')
        self.validate_thresholds(optional=True)

    def run(self):
        if not which('docker'):
            raise UnknownError("'docker' command not found in $PATH")
        process = subprocess.Popen(['docker', 'images', '{repo}'.format(repo=self.docker_image)],
                                   stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        (stdout, stderr) = process.communicate()
        exitcode = process.returncode
        log.debug('stdout:\n%s', stdout)
        log.debug('stderr:\n%s', stderr)
        log.debug('exitcode: %s', exitcode)
        if stderr:
            raise UnknownError(stderr)
        if exitcode != 0:
            raise UnknownError("exit code returned was '{0}': {1} {2}".format(exitcode, stdout, stderr))
        if not stdout:
            raise UnknownError('no output from docker images command!')
        self.parse(stdout)

    def parse(self, stdout):
        if isPythonMinVersion(3):
            output = [_ for _ in str(stdout).split(r'\n') if _]
        else:
            output = [_ for _ in str(stdout).split('\n') if _]
        log.debug('output = %s', output)
        if len(output) < 2:
            raise CriticalError("docker image '{repo}' not found! Does not exist or has not been pulled yet?"\
                                .format(repo=self.docker_image))
        tags = set()
        for line in output[1:]:
            log.debug('line: %s', line)
            line_parts = line.split()
            if len(line_parts) > 1:
                tags.add(line_parts[1])
        tags = [tag for tag in tags if tag and tag != '<none>']
        tags = sorted(list(tags))
        if log.isEnabledFor(logging.DEBUG):
            for tag in tags:
                log.debug('found tag: %s', tag)
        if len(tags) > 1:
            raise UnknownError('too many results returned - did you forget to suffix a specific :tag to ' + \
                               '--docker-image? (eg. :latest, :1.1). The following tags were found: ' + \
                               ', '.join(tags)
                              )
        header_line = output[0]
        docker_image_line = output[1]
        image_header = ' '.join(header_line.split()[2:4])
        log.debug('image header column: %s', image_header)
        if image_header != 'IMAGE ID':
            raise UnknownError("3rd column in header '{0}' is not 'IMAGE ID' as expected, parsing failed!"\
                               .format(image_header))
        self.msg = "docker image '{repo}'".format(repo=self.docker_image)
        self.check_id(docker_image_line)
        self.check_size(docker_image_line)

    def check_id(self, docker_image_line):  # lgtm [py/similar-function]
        #_id = output[1][name_len + 10:name_len + 10 + 20].strip()
        _id = docker_image_line.split()[2]
        log.debug('id: %s', _id)
        self.msg += ", id = '{id}'".format(id=_id)
        if self.expected_id:
            log.debug('checking expected --id')
            if not re.match(r'(sha\d+:)?\w+', _id):
                raise UnknownError("{msg} not in sha format as expected! {support}"\
                                   .format(msg=self.msg, support=support_msg()))
            if _id != self.expected_id:
                self.critical()
                self.msg += " (expected id = '{0}')".format(self.expected_id)
        return _id

    def check_size(self, docker_image_line):
        match = re.search(r'(\d+(?:\.\d+)?)\s*([KMG]B)\s*$', docker_image_line)
        if match:
            size = match.group(1)
            units = match.group(2).strip()
            log.debug("size: %s", size)
            log.debug("units: %s", units)
            size_in_bytes = expand_units(size, units)
            log.debug("size in bytes: %s", size_in_bytes)
        else:
            raise UnknownError('failed to parse size. {0}'.format(support_msg()))
        self.msg += ", size = {size} {units}".format(size=size, units=units)
        log.debug('checking size %s against thresholds', size_in_bytes)
        self.check_thresholds(size_in_bytes)
        return size_in_bytes


if __name__ == '__main__':
    CheckDockerImage().main()
