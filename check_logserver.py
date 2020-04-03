#!/usr/bin/env python
#
#  Author: Hari Sekhon
#  Date: 2007-06-04 11:20:59 +0100 (Mon, 04 Jun 2007)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

"""Nagios plugin to check a Syslog-NG/MySQL logserver. Puts a test message \
into the logging system via tcp and then tries to retrieve it from the back \
end MySQL database to check that it was properly received"""

# TODO: add a log delete switch to remove the just inserted log -h

from __future__ import print_function

__author__ = "Hari Sekhon"
__title__ = "Nagios Plugin to check Syslog-NG/MySQL logservers"
__version__ = "0.9.1"

# Nagios Standard Exit Codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# Additional to support specific help returns
HELP = 4

# pylint: disable=wrong-import-position
import os
import re
import sys
import time
import signal
import socket
from optparse import OptionParser
try:
    import MySQLdb
    from MySQLdb import MySQLError
except ImportError:
    print("You must have the MySQLdb python library", end=' ')
    print("installed to run this plugin")
    sys.exit(CRITICAL)

SCRIPTNAME = os.path.basename(sys.argv[0])


def end(exitcode, message):
    """prints a message and exits. Two args are required, first the exit
    code and then the message to print"""

    if exitcode == OK:
        print("LogServer OK: %s" % message)
    elif exitcode == WARNING:
        print("WARNING: %s" % message)
    elif exitcode == CRITICAL:
        print("CRITICAL: %s" % message)
    elif exitcode == HELP:
        print("UNKNOWN: %s. See --help for details" % message)
        # return UNKNOWN as standard, discard internal help code
        exitcode = UNKNOWN
    else:
        print("UNKNOWN: %s" % message)
        # force safety net of anything unknown to be overridden
        # to a logical unknown status code to comply with Nagios
        exitcode = UNKNOWN

    sys.exit(exitcode)


class LogServerTester(object):
    """Class to create object containing logserver test, holding all variables
    and methods to perform the test"""

    def __init__(self):
        """Instantiate variables to defaults"""

        # starting values of variables used/defined later
        self.conn_type = "TCP"
        self.log = ""
        self.re_validation = None

        # Input variables
        self.delay = None
        self.logserver = None
        self.logserver_port = None
        self.mysql_column = None
        self.mysql_db = None
        self.mysql_port = None
        self.mysql_server = None
        self.mysql_table = None
        self.password = None
        self.timeout = None
        self.udp = False
        self.username = None
        self.verbosity = 0

        # Default variables which are based on the most commonly
        # use database names and the default ports for each service

        self.default_delay = 0
        self.default_logserver_port = 514
        self.default_mysql_column = "msg"
        self.default_mysql_db = "syslog"
        self.default_mysql_port = 3306
        self.default_mysql_table = "logs"
        self.default_timeout = 30
        self.default_udp = False


    def generate_log(self):
        """Generates and returns a unique timestamped log string to feed the \
        logserver. Log string is not ended by a newline"""

        if self.udp is True:
            self.conn_type = "UDP"

        program = SCRIPTNAME

        # USER facility
        facility = 1
        # DEBUG priority
        priority = 7
        pri = facility * 8 + priority

        hostname = socket.gethostname().lower()

        timestamp = time.strftime('%b %d %T')
        epoch = time.time()

        # format follows syslog standard and is in the form
        # <pri>timestamp hostname program: log message epoch

        # newline is not added as the newline is not put into
        # the database and we want to query the database for
        # this pure log later on
        log = "<%s>%s %s %s: Nagios Log Server %s Check %s" % \
            (pri, timestamp, hostname, program, self.conn_type, epoch)

        return log


    def send_log(self):
        """send the log to the logserver"""

        if self.udp:
            self.vprint(2, "creating udp connection to logserver")
            logserver_socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        else:
            self.vprint(2, "creating tcp connection to logserver")
            logserver_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.vprint(3, "connecting to %s on port %s..." \
                       % (self.logserver, self.logserver_port))
        try:
            logserver_socket.connect((self.logserver, self.logserver_port))
            # Newline added here as it is what separates one syslog message
            # from the next
            logserver_socket.send(self.log+"\n")
            logserver_socket.close()
        except (socket.error, socket.timeout) as socket_error:
            if self.verbosity >= 1:
                # You can only get a socket error on tcp, udp is stateless
                # fire and forget so you won't get a socket error, hence
                # I write "tcp port" here.
                end(CRITICAL, "failed to send log to logserver " \
                            + "'%s' on tcp " % self.logserver \
                            + "port '%s' - '%s'" \
                                % (self.logserver_port, socket_error[1]))
            else:
                end(CRITICAL, "failed to send log to logserver - '%s'" \
                                                % (socket_error[1]))
        self.vprint(2, "log sent")


    def set_timeout(self):
        """sets an alarm to time out the test"""

        if self.timeout == 1:
            self.vprint(3, "setting plugin timeout to %s second" \
                                                                % self.timeout)
        else:
            self.vprint(3, "setting plugin timeout to %s seconds"\
                                                                % self.timeout)

        signal.signal(signal.SIGALRM, self.sighandler)
        signal.alarm(self.timeout)


    # pylint: disable=unused-argument
    def sighandler(self, _discarded, _discarded2):
        """Function to be called by signal.alarm to kill the plugin"""

        end(CRITICAL, "logserver plugin has self terminated after exceeding " \
                    + "the timeout (%s seconds)" % self.timeout)


    def test_logserver(self):
        """Starts the logserver test"""
        # This function should exit with an error if any variables fail input
        # validation
        self.validate_variables()

        # First let's make sure this test doesn't take more than the
        # timeout threshold to follow nagios standards
        self.set_timeout()

        self.log = self.generate_log()

        # Should never happen but  it doesn't hurt to be defensive
        if self.log == "":
            end(CRITICAL, "Log generation failed")

        self.vprint(3, "log is '%s'" % self.log)
        self.vprint(2, "now sending log...")

        self.send_log()

        self.vprint(2, "waiting %s seconds before 2nd part of check" \
                                                                % self.delay)

        time.sleep(self.delay)

        self.vprint(2, "now testing for log in mysql database")

        returncode = self.test_mysql_server()

        return returncode


    def test_mysql_server(self):
        """Connects to the MySQL server and queries for log"""

        if self.verbosity >= 3:
            print("creating connection to mysql server")
            print("host = '%s'" % self.mysql_server)
            print("port = '%s'" % self.mysql_port)
            print("user = '%s'" % self.username)
            print("password = '%s'" % self.password)
            print("mysql_db = '%s'" % self.mysql_db)

        try:
            db_connection = MySQLdb.connect(host=self.mysql_server,
                                            user=self.username,
                                            passwd=self.password,
                                            db=self.mysql_db,
                                            port=self.mysql_port)
        except MySQLError as mysql_error:
            end(CRITICAL, "error connecting to database - %s" % mysql_error[1])

        self.vprint(2, "connected to database")

        cursor = db_connection.cursor()

        log_message = ""

        for message_part in self.log.split()[4:]:
            log_message += message_part + " "

        log_message = log_message.rstrip(" ")

        self.vprint(2, "extracted log message body from log")
        self.vprint(2, "log message is '%s'" % log_message)

        # security is maintained by a combinarion of `` and restrictive
        # regex validation the validate functions. MySQLdb must take care of
        # the log value but this is not an input variable anyway.
        query = "select count(*) from `%s` where `%s`=%%s" \
                                % (self.mysql_table, self.mysql_column)

        # This query will be slow and necessitates the need for a long default
        # timeout, as this is not suitable for an index and therefore must do a
        # full table scan
        # select count(*) from logs where msg='logmessage'
        self.vprint(2, "querying mysql database for log...")
        self.vprint(3, query % "'" + log_message + "'")
        try:
            # Use the parameter bit from the db api here because we can for the
            # value of log message, quoting is ok there
            # AS NOTED ABOVE, SECURITY IS HANDLED BY RESTRICTIVE REGEX OF
            # SAFE PARAMETERS IN MAIN FUNCTION -h
            cursor.execute(query, (log_message,))
        except MySQLError as mysql_error:
            end(CRITICAL, "error querying mysql server for log - %s" \
                                                        % mysql_error[1])
        result = cursor.fetchall()
        if not result:
            end(CRITICAL, "No results returned from database query! " \
                        + "Possible database problem")
        try:
            number_of_logs = result[0][0]
        except IndexError:
            end(CRITICAL, "Error processing result returned from MySQL server, " \
                        + "please run with -vvv")

        self.vprint(2, "number of logs matching message body: %s" \
                                                            % number_of_logs)

        if number_of_logs == 1:
            end(OK, "log successfully sent and entered into database")
        elif number_of_logs > 1:
            end(WARNING, "more that one log detected, non-unique test log\
message has been inserted into the database")
        elif number_of_logs == 0:
            end(CRITICAL, "log failed to appear in the logserver back end")
        else:
            end(CRITICAL, "unknown number of logs detected")

        return UNKNOWN


    def validate_credentials(self):
        """Validates the username and password for use in
        the MySQL connection"""

        # No regex validation here since the MySQLdb library seems to be safe
        # against injection on these variables
        if self.username is None:
            end(HELP, "You must enter a username for the MySQL database")

        if self.password is None:
            end(HELP, "You must enter a password for the MySQL database")


    def validate_delay(self):
        """Validates delay and exits if invalid"""

        if self.delay is None:
            self.delay = self.default_delay

        try:
            self.delay = int(self.delay)
            if not 0 <= self.delay <= 3600:
                raise ValueError
        except ValueError:
            end(HELP, "delay is the number of seconds between sending a " \
                    + "log and testing the MySQL database for it. It must " \
                    + "be a whole number between 0 and 3600 seconds")


    def validate_logserver(self):
        """Validates logserver and exits if invalid"""

        if self.logserver is None:
            end(HELP, "You must enter a logserver hostname or ip address")

        if not self.re_validation.match(self.logserver):
            end(UNKNOWN, "logserver name/ip address supplied contains " \
                       + "unusable characters")


    def validate_logserver_port(self):
        """Validates logserver variable and exits if invalid"""

        if self.logserver_port is None:
            self.logserver_port = self.default_logserver_port

        try:
            self.logserver_port = int(self.logserver_port)
            if not 1 <= self.logserver_port <= 65535:
                raise ValueError
        except ValueError:
            end(UNKNOWN, "logserver port number must a whole number " \
                       + "between 1 and 65535")



    def validate_mysql_column(self):
        """Validates the mysql column name and exits if invalid"""

        if self.mysql_column is None:
            self.mysql_column = self.default_mysql_column

        if not self.re_validation.match(self.mysql_column):
            end(UNKNOWN, "mysql column name supplied contains unusable " \
                       + "characters")


    def validate_mysql_db(self):
        """Validates the mysql database name and exits if invalid"""

        if self.mysql_db is None:
            self.mysql_db = self.default_mysql_db

        if not self.re_validation.match(self.mysql_db):
            end(UNKNOWN, "mysql database name supplied contains unusable " \
                       + "characters")


    def validate_mysql_port(self):
        """Validates the mysql port and exits if invalid"""

        if self.mysql_port is None:
            self.mysql_port = self.default_mysql_port

        try:
            self.mysql_port = int(self.mysql_port)
            if not 1 <= self.mysql_port <= 65535:
                raise ValueError
        except ValueError:
            end(UNKNOWN, "mysql port number must be a whole number between " \
                       + "1 and 65535")


    def validate_mysql_server(self):
        """Validates the mysql server, makes it default to the same host as
        the logserver. Exits if invalid name"""

        # This test should be after the logserver test to keep error messages
        # sane, ie if logserver is invalid, you don't want to test mysql_server
        # first and end up with a message saying the mysql_server variable in
        # invalid when actually you put in an invalid logserver
        if self.mysql_server is None:
            self.mysql_server = self.logserver

        if not self.re_validation.match(self.mysql_server):
            end(UNKNOWN, "mysql server name/ip address supplied contains " \
                       + "unusable characters")


    def validate_mysql_table(self):
        """Validates the mysql table name and exits if invalid"""

        if self.mysql_table is None:
            self.mysql_table = self.default_mysql_table

        if not self.re_validation.match(self.mysql_table):
            end(HELP, "mysql table name supplied contains unusable " \
                       + "characters")


    def validate_timeout(self):
        """Validates timeout and exits if invalid"""

        if self.timeout is None:
            self.timeout = self.default_timeout

        try:
            self.timeout = int(self.timeout)
            if not 1 <= self.timeout <= 3600:
                raise ValueError
        except ValueError:
            end(HELP, "timeout is in seconds and must be a " \
                       + "whole number between 1 and 3600 (1 hour)")


    def validate_udp(self):
        """Validates the udp switch setting and sets the appropriate
        connection type"""

        if not self.udp:
            pass
        elif self.udp:
            self.conn_type = "UDP"
        else:
            end(CRITICAL, "Invalid udp variable specified, value must be " \
                        + "True/False")


    def validate_variables(self):
        """Performs validation against all object variables. Should be called
        before or by test before using those variables"""

        # security note against injection: these sanity checks are necessary
        # because of the weakness of the MySQLdb library quoting issue, but
        # username and password is not vulnerable by my testing for cli
        # injection so they are not tested here.
        self.re_validation = re.compile(r'^[\w\d\.-]+$')

        # validate logserver should be before validate mysql_server
        # see validate_mysql_server for why
        # every input variable except for verbosity which is an
        # incremental counter should be validated here

        # validate_credentials takes care of the username and password
        self.validate_logserver()
        self.validate_logserver_port()
        self.validate_credentials()

        self.validate_mysql_server()
        self.validate_mysql_port()
        self.validate_mysql_db()
        self.validate_mysql_table()
        self.validate_mysql_column()

        self.validate_delay()
        self.validate_timeout()
        self.validate_verbosity()


    def validate_verbosity(self):
        """Validates that verbosity is a numeric integer, exits if not"""

        if self.verbosity is None:
            self.verbosity = 0

        try:
            self.verbosity = int(self.verbosity)
            if self.verbosity < 0:
                raise ValueError
        except ValueError:
            end(CRITICAL, "Invalid verbosity type, must be positive numeric " \
                        + "integer")


    def vprint(self, verbosity, message):
        """Prints messages based on the verbosity level. Takes 2 arguments,
        verbosity, and the message. If verbosity is equal to or greater than
        the minimum verbosity then the message is printed"""

        if self.verbosity >= verbosity:
            print(str(message))


def main():
    """parses command line options, instantiates the tester and calls initial
    method to test the logserver"""

    tester = LogServerTester()
    parser = OptionParser()

    parser.add_option("-H",
                      "--logserver",
                      dest="logserver",
                      help="The logserver to test")

    parser.add_option("-p",
                      "--port",
                      "--logserver-port",
                      dest="logserver_port",
                      help="The port of the logserver. Optional, defaults to" \
                          +" port %s" % tester.default_logserver_port)

    parser.add_option("-U",
                      "--username",
                      dest="username",
                      help="The MySQL user to log in as to test that the log" \
                          +" was created in the back end database")

    parser.add_option("-P",
                      "--password",
                      dest="password",
                      help="The MySQL password to log in with to test that " \
                          +"the log was created in the back end database")

    parser.add_option("-M",
                      "--mysql-server",
                      dest="mysql_server",
                      help="The mysql server hostname or ip address. " \
                          +"Optional, defaults to the same address as the " \
                          +"logserver.")

    parser.add_option("-m",
                      "--mysql-port",
                      dest="mysql_port",
                      help="The port number of the MySQL database. Optional" \
                          +", defaults to %s" % tester.default_mysql_port)

    parser.add_option("-D",
                      "--mysql-db",
                      dest="mysql_db",
                      help="The MySQL database instance to query for the log" \
                          +". Optional, defaults to '%s'" \
                                                    % tester.default_mysql_db)

    parser.add_option("-T",
                      "--mysql-table",
                      dest="mysql_table",
                      help="The MySQL table to query for the log. Optional" \
                          +", defaults to '%s'" % tester.default_mysql_table)

    parser.add_option("-C",
                      "--mysql-column",
                      dest="mysql_column",
                      help="The MySQL column in which the log message is " \
                          +"kept. Optional, defaults to '%s'" \
                                                % tester.default_mysql_column)

    parser.add_option("-d",
                      "--delay",
                      dest="delay",
                      help="Delay between sending the log and querying the "\
                          +"logserver backend mysql database for the log " \
                           +"message. This is useful if the logserver is " \
                           +"heavily utilized or has batch inserts, as it " \
                           +"allows the logserver more time to process the " \
                           +"log and insert it into the database before the " \
                           +"second part of the test searches for it. Valid " \
                           +"range is between 0 and 3600 seconds. Defaults " \
                           +"to %s seconds" % tester.default_delay)

    parser.add_option("-t",
                      "--timeout",
                      dest="timeout",
                      help="sets a timeout in seconds after which the " \
                          +"plugin will exit (defaults to %s). " \
                                                     % tester.default_timeout \
                          +"Recommended that this is used to increase " \
                          +"timeout if mysql server takes more than 30 " \
                          +"seconds to query logs table as it usually will. " \
                          +"Best used in conjunction with passive service " \
                          +"check if longer than 30 seconds")

    parser.add_option("-u",
                      "--udp",
                      action="store_true",
                      dest="udp",
                      help="Send the log to the logserver by udp. Default " \
                          +"is to send the log via %s" % tester.conn_type)

    parser.add_option("-v",
                      "--verbose",
                      action="count",
                      dest="verbosity",
                      help="Verbose mode. Good for testing plugin. By " \
                          +"default only one result line is printed as per " \
                          +"Nagios standards")

    parser.add_option("-V",
                      "--version",
                      action="store_true",
                      dest="version",
                      help="Print version number and exit")

    (options, args) = parser.parse_args()

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    # Very important. Input validation is done in the object itself
    # before these variables are used.
    tester.delay = options.delay
    tester.logserver = options.logserver
    tester.logserver_port = options.logserver_port
    tester.mysql_column = options.mysql_column
    tester.mysql_db = options.mysql_db
    tester.mysql_port = options.mysql_port
    tester.mysql_server = options.mysql_server
    tester.mysql_table = options.mysql_table
    tester.password = options.password
    tester.timeout = options.timeout
    tester.udp = options.udp
    tester.username = options.username
    tester.verbosity = options.verbosity

    if options.version:
        print(__version__)
        sys.exit(UNKNOWN)

    start_time = time.time()

    #returncode, output = tester.test_logserver()
    returncode = tester.test_logserver()

    finish_time = time.time()
    total_time = finish_time - start_time

    #if output:
    #    print "%s. Test completed in %.3f seconds" % (output, total_time)
    #else:
    print("No output returned by logserver test! Test took %.3f seconds" \
                                                                    % total_time)
    sys.exit(returncode)


if __name__ == "__main__":
    try:
        main()
        sys.exit(UNKNOWN)
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
