#!/usr/bin/env python
#
#  Author: Hari Sekhon and Maxwgod
#  Date: 2021-09-01 22:00:01 +0000 (Fri, 13 Apr 2007)
#
#  http://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying LICENSE file
#

""" This script is intended to be used with the open source OpenSSH client
program "sftp" and "sshpass". It is also intended to test an OpenSSH sftp server.
Your mileage may vary if you try to use it with something else. -h """

# TODO: meant to rewrite this with Paramiko years ago but didn't get round to it...

from __future__ import print_function

import os
import signal
import sys
import re
import shutil
from subprocess import Popen, PIPE, STDOUT
from optparse import OptionParser

__author__ = "Hari Sekhon and MaxwNEBR"
__title__ = "Nagios Plugin for SFTP/SSHPASS"
__version__ = "1.9.0"

# Nagios Standard Exit Codes
OK = 0
WARNING = 1
CRITICAL = 2
UNKNOWN = 3

# Default option variables
default_port = 22
default_timeout = 30
strictkeyoption = ""


def sighandler(_discarded, _discarded2):  # pylint: disable=unused-argument
    """function to be called by signal.alarm to kill the plugin"""

    print("SFTP CRITICAL: plugin has self terminated after exceeding the \
timeout")
    sys.exit(CRITICAL)


def which(executable):
    """takes an executable name as the only arg and tests if it is in the path.
    Returns the full path of the executable if it exists in path, or None if it
    does not"""

    for basepath in os.environ['PATH'].split(os.pathsep):
        path = os.path.join(basepath, executable)
        if os.path.isfile(path):
            return path
    return None


def end(status, message):
    """exits the plugin with first arg as the return code and the second
    arg as the message to output"""

    if status == OK:
        if message:
            print("OK: %s" % message)
        else:
            print("SFTP OK: logged in successfully")
        sys.exit(OK)
    elif status == WARNING:
        print("WARNING: %s" % message)
        sys.exit(WARNING)
    elif status == CRITICAL:
        print("CRITICAL: %s" % message)
        sys.exit(CRITICAL)
    else:
        print("UNKNOWN: %s" % message)
        sys.exit(UNKNOWN)


def run(cmd, verbosity, dirs, files, grepcomd, server):
    """takes a command as the single argument, runs it and returns
    a tuple of the exitcode and the output"""

    if verbosity >= 2:
        print("%s" % cmd)

    process = Popen(cmd, shell=True, stdin=PIPE, stdout=PIPE, stderr=PIPE)
    if dirs and not files and not grepcomd:
        (out, err) = process.communicate("ls -la %s" % dirs[0])
        erro = err.lstrip("Connected to %s..." % server).strip()
        if erro:
            end(CRITICAL, "Directory not found %s" % dirs[0])
        end(OK, "Directory found %s" % dirs[0])
    elif grepcomd and files:
        if os.path.isdir("./tempsftp"):
            shutil.rmtree("./tempsftp")
        os.mkdir("./tempsftp")
        if dirs:
            (out, err) = process.communicate("get %s/%s ./tempsftp/" % (dirs[0],files[0]))
            process.wait()
        else:
            (out, err) = process.communicate("get %s ./tempsftp/" % files[0])
            process.wait()
        erro = err.lstrip("Connected to %s..." % server).strip()
        if erro:
            end(CRITICAL, erro)
        save = []
        with open('./tempsftp/%s' % files[0],'r') as f:
            for line in f:
                if any(s in line.split() for s in grepcomd):
                    save.append([line.strip()])
        if save:
            end(CRITICAL, save)
        end(OK, "Not find %s" % grepcomd)
    else:
        (output, err) = process.communicate("ls -la %s" % dirs[0])

    if verbosity >= 3:
        print("%s" % output)

    return process.returncode, output


# pylint: disable=unused-variable,unused-argument
def test_sftp(sftp, server, port, user, password, sshkey, nostricthostkey, \
                                                     files, dirs, verbosity, grepcomd):

    """tests the sftp server using the supplied args"""

    if user:
        if verbosity >= 2:
            print("setting username to %s" % user)
        useroption = "-oUser=%s " % user
    else:
        useroption = ""

    if sshkey:
        sshkeyoption = "-oIdentityFile=%s " % sshkey
    else:
        sshkeyoption = ""

    if nostricthostkey:
        if verbosity >= 1:
            print("disabling strict host key checking")
        nostricthostkeyoption = "-oStrictHostKeyChecking=no "
    else:
        nostricthostkeyoption = ""

    if password:
        # NumberOfPasswordPrompts=0 would also do here.
        # PasswordAuthentication=no doesn't work though.
        # Preferred Authentications limits it to publickey only
        cmd = "sshpass -p%(password)s %(sftp)s \
-oPort=%(port)s \
%(useroption)s\
%(sshkeyoption)s\
-oPreferredAuthentications=password \
%(nostricthostkeyoption)s\
%(server)s" % vars()
    else:
        cmd = "%(sftp)s \
-oPort=%(port)s \
%(useroption)s\
%(sshkeyoption)s\
-oPreferredAuthentications=publickey \
%(nostricthostkeyoption)s\
%(server)s" % vars()

    result, output = run(cmd, verbosity, dirs, files, grepcomd, server)

    output2 = output

    output2 = output2.lstrip("Connecting to %s..." % server)
    output2 = output2.replace("\r", "")

    if verbosity < 2:
        output2 = output2.replace("\n", ", ")
        output2 = output2.lstrip(", ")
        output2 = output2.rstrip(", ")
    
    if result != OK:
        end(CRITICAL, output2)

    if files or dirs:
        test_items(output, files, dirs, verbosity)

    end(result, output2)

    return UNKNOWN


def test_items(output, files, dirs, verbosity):
    """takes the output of the sftp directory listing and a list of dirs and
    verifies the dirs exist in the listing of the output"""

    lines = output.split("\n")
    
    if dirs and not files:
        for item in dirs:
            found = False
            for line in lines:
                line = line.split()
                if len(line) == 9:
                    if item == line[8] and line[0][0] == "d":
                        found = True
                        if verbosity >= 2:
                            print("found '%s'" % (item))
                        continue
            if not found:
                end(CRITICAL, "Directory '%s' not found on sftp server" % item)
        end(OK,"Directorys found %s" % dirs)

    if files:
        for item in files:
            found = False
            for line in lines:
                line = line.split()
                if len(line) == 9:
                    if item == line[8] and line[0][0] != "d":
                        found = True
                        if verbosity >= 2:
                            print("found '%s'" % (item))
                        continue
            if not found:
                end(CRITICAL, "File '%s' not found on sftp server" % item)
        end(OK,"Files found %s" % files)

    return OK


def main():
    """main function, parses args and calls test function"""

    parser = OptionParser()
    parser.add_option("-H", dest="server", help="server name or ip address")
    parser.add_option("-p", dest="port",
                      help="port number of the sftp service on the server (defaults to %s)" % default_port)
    parser.add_option("-U", dest="user",
                      help="user name to connect as (defaults to current user)")
    parser.add_option("-P", dest="password",
                      help="password to use SFTP.")
    parser.add_option("-k", dest="sshkey",
                      help="ssh private key to use for authentication")
    parser.add_option("-d", action="append", dest="directory",
                      help="test for the existence of a directory.")
    parser.add_option("-f", action="append", dest="file",
                      help="test for the existence of a file. Can use multiple times to \
 check for the existence of multiple files.")
    parser.add_option("-g", action="append", dest="grepfiles",
                      help="Texts to find in file. Can use multiple times.")
    parser.add_option("-s", action="store_true", dest="nostricthostkey",
                      help="disable strict host key checking. This will auto-accept the \
remote host key. Otherwise you first have to add the ssh host key of the sftp \
server to known hosts before running the test or it will fail (although by \
default you will be prompted to accept the host key if it is run \
interactively)")
    parser.add_option("-t", dest="timeout",
                      help="sets a timeout after which the plugin will exit (defaults to %s)"\
                                                            % default_timeout)
    parser.add_option("-v", action="count", dest="verbosity",
                      help="adds verbosity. Use multiple times for cumulative effect. \
By default only 1 line of output is printed")

    options, args = parser.parse_args()

    server = options.server
    port = options.port
    user = options.user
    password = options.password
    sshkey = options.sshkey
    files = options.file
    directories = options.directory
    grepcomd = options.grepfiles
    timeout = options.timeout
    verbosity = options.verbosity
    nostricthostkey = options.nostricthostkey

    if args:
        parser.print_help()
        sys.exit(UNKNOWN)

    if not timeout:
        timeout = default_timeout

    try:
        timeout = int(timeout)
    except ValueError:
        end(UNKNOWN, "timeout value must be a numeric integer")

    if timeout < 1 or timeout > 3600:
        end(UNKNOWN, "timeout is in seconds and must be a number between \
1 and 3600 (1 hour)")

    signal.signal(signal.SIGALRM, sighandler)
    signal.alarm(timeout)


    sftp = which("sftp")

    if not sftp:
        end(UNKNOWN, "sftp could not be found in the path")
    elif not os.access(sftp, os.X_OK):
        end(UNKNOWN, "%s is not executable" % sftp)

    if not server:
        end(UNKNOWN, "You must enter a server name or ip address to connect to")

    if not port:
        port = default_port

    try:
        port = int(port)
    except ValueError:
        end(UNKNOWN, "port number must be a numeric integer")

    if port < 1 or port > 65335:
        end(UNKNOWN, "port number must be between 1 and 65535")

    if sshkey:
        if verbosity >= 2:
            print("using private ssh key for authentication '%s'" % sshkey)
        if not os.path.isfile(sshkey):
            end(UNKNOWN, "cannot find ssh key file \"%s\"" % sshkey)
        elif not os.access(sshkey, os.R_OK):
            end(UNKNOWN, "ssh key file \"%s\" is not readable" % sshkey)


    test_sftp(sftp, server, port, user, password, sshkey, nostricthostkey, \
                                                files, directories, verbosity, grepcomd)

    # Things should never fall through to here
    sys.exit(UNKNOWN)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Caught Control-C...")
        sys.exit(CRITICAL)
