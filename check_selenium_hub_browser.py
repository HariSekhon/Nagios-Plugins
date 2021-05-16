#!/usr/bin/env python
#  coding=utf-8
#  vim:ts=4:sts=4:sw=4:et
#  args: --browser chrome -v
#
#  Author: Hari Sekhon
#  Date: 2021-05-12 09:55:01 +0100 (Wed, 12 May 2021)
#
#  https://github.com/HariSekhon/pytools
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn
#  and optionally send me feedback to help steer this or other code I publish
#
#  https://www.linkedin.com/in/HariSekhon
#

"""
Nagios Plugin to test a Selenium Grid Hub / Selenoid browser eg. FIREFOX, CHROME
against a given URL and content (defaults to google.com)

URL to test defaults to 'google.com' checking for content 'google'
If you define a different URL then you must specify a --content or --regex validation otherwise none is used

Example:

    ./check_selenium_hub_browser.py --host <selenium_hub_host> --browser chrome

    ./check_selenium_hub_browser.py --hub-url http://<selenium_hub_host>:4444/wd/hub/ --browser firefox

Where browsers are one or more of these and must be supported by the remote Selenium Hub:

ANDROID
CHROME
EDGE
FIREFOX
HTMLUNIT
HTMLUNITWITHJS
INTERNETEXPLORER
IPAD
IPHONE
OPERA
PHANTOMJS
SAFARI
WEBKITGTK

Examples:

    ./check_selenium_hub_browser.py --host x.x.x.x

    ./check_selenium_hub_browser.py --host x.x.x.x FIREFOX CHROME

    ./check_selenium_hub_browser.py --host x.x.x.x --browser chrome --url google.com --content google
    ./check_selenium_hub_browser.py --host x.x.x.x --browser firefox --url google.com --regex 'goog.*'


If Selenium Hub doesn't have a browser available for you in time,
you'll end up waiting in the queue until you receive a generic timeout error:

    UNKNOWN: self timed out after 30 seconds


Tested on Selenium Grid Hub v.3.141.59, v4.0.0 and Selenoid 1.10.1
"""

from __future__ import absolute_import
from __future__ import division
from __future__ import print_function
from __future__ import unicode_literals

import os
import re
import sys
import time
import traceback
try:
    import selenium
    from selenium import webdriver
    from selenium.webdriver.common.desired_capabilities import DesiredCapabilities
except ImportError:
    print(traceback.format_exc(), end='')
srcdir = os.path.abspath(os.path.dirname(__file__))
libdir = os.path.join(srcdir, 'pylib')
sys.path.append(libdir)
try:
    # pylint: disable=wrong-import-position
    from harisekhon import NagiosPlugin
    from harisekhon.utils import log, validate_host, validate_port, validate_url, validate_regex, validate_alnum
    from harisekhon.utils import UnknownError
except ImportError:
    print(traceback.format_exc(), end='')
    sys.exit(4)

__author__ = 'Hari Sekhon'
__version__ = '0.3'


# pylint: disable=too-many-instance-attributes
class CheckSeleniumHubBrowser(NagiosPlugin):

    def __init__(self):
        # Python 2.x
        super(CheckSeleniumHubBrowser, self).__init__()
        # Python 3.x
        # super().__init__()
        self.host = None
        self.port = None
        self.protocol = 'http'
        self.name = 'Selenium Hub'
        self.path = 'wd/hub'
        self.hub_url = None
        self.browser = None
        self.url_default = 'http://google.com'
        self.url = self.url_default
        self.expected_content = None
        self.expected_content_default = 'google'
        self.expected_regex = None
        self.timeout_default = 30
        self.msg = 'Selenium Hub msg not defined yet'

    def add_options(self):
        super(CheckSeleniumHubBrowser, self).add_options()
        self.add_hostoption(name='Selenium Hub', default_port=4444)
        self.add_opt('-U', '--hub-url', help='Selenium Hub URL (overrules --host/--port/--ssl)')
        self.add_opt('-b', '--browser', help='Browser to request from Selenium Hub')
        self.add_opt('-u', '--url', default=self.url_default,
                     help='URL to use for the test (default: {})'.format(self.url_default))
        self.add_opt('-c', '--content', help='URL content to expect')
        self.add_opt('-r', '--regex', help='URL content to expect')
        self.add_opt('-S', '--ssl', action='store_true', help='Use SSL to connect to Selenium Hub')

    def process_options(self):
        super(CheckSeleniumHubBrowser, self).process_options()
        self.hub_url = self.get_opt('hub_url')
        if self.hub_url:
            validate_url(self.hub_url, 'hub')
        else:
            self.host = self.get_opt('host')
            self.port = self.get_opt('port')
            validate_host(self.host)
            validate_port(self.port)
            if self.get_opt('ssl') or int(self.port) == 443:
                self.protocol = 'https'
            self.hub_url = '{protocol}://{host}:{port}/{path}'\
                           .format(protocol=self.protocol, \
                                   host=self.host, \
                                   port=self.port, \
                                   path=self.path)
        self.url = self.get_opt('url')
        if ':' not in self.url:
            self.url = 'http://' + self.url
        validate_url(self.url)
        self.browser = self.get_opt('browser')
        if self.browser:
            self.browser = self.browser.upper()
        validate_alnum(self.browser, 'browser')
        self.expected_content = self.get_opt('content')
        self.expected_regex = self.get_opt('regex')
        if self.expected_regex:
            validate_regex(self.expected_regex)
            self.expected_regex = re.compile(self.expected_regex)
        elif self.url == self.url_default:
            self.expected_content = self.expected_content_default

    def check_selenium(self):
        log.info("Connecting to '%s' for browser '%s'", self.hub_url, self.browser)
        driver = webdriver.Remote(
            command_executor=self.hub_url,
            desired_capabilities=getattr(DesiredCapabilities, self.browser)
        )
        log.info("Checking url '%s'", self.url)
        driver.get(self.url)
        content = driver.page_source
        title = driver.title
        driver.quit()
        self.msg = "Selenium Hub browser '{}' fetched web page".format(self.browser.lower())
        if self.verbose:
            self.msg += " for url '{}'".format(self.url)
        if self.expected_regex:
            log.info("Checking url content matches regex")
            if not self.expected_regex.search(content):
                self.warning()
                self.msg += " but page html failed regex search"
        elif self.expected_content:
            log.info("Checking url content matches '%s'", self.expected_content)
            if self.expected_content not in content:
                self.warning()
                self.msg += " but page html failed content match"
        # not really recommended but in this case we cannot predict
        # what to expect on a random url if not specified by --content/--regex (provided in the default test case)
        #
        # https://www.selenium.dev/documentation/en/worst_practices/http_response_codes/
        elif '404' in title:
            self.warning()
            self.msg = "Selenium Hub browser '{}' received 404 in title ".format(self.browser.lower()) + \
                       "for web page '{}' ".format(self.url) + \
                       "(if this is expected, specify --content / --regex to check instead): {}".format(title)

    def run(self):
        self.ok()
        start_time = time.time()
        try:
            self.check_selenium()
        except selenium.common.exceptions.WebDriverException as _:
            raise UnknownError('Selenium WebDriverException: {}'.format(_))
        query_time = time.time() - start_time
        log.info('Finished check in {:.2f} secs'.format(query_time))
        self.msg += ' | query_time={:.2f}s'.format(query_time)


if __name__ == '__main__':
    CheckSeleniumHubBrowser().main()
