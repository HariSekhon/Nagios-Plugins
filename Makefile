#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  https://github.com/harisekhon/nagios-plugins
#
#  License: see accompanying Hari Sekhon LICENSE file
#
#  If you're using my code you're welcome to connect with me on LinkedIn and optionally send me feedback
#  to help improve or steer this or other code I publish
#
#  https://www.linkedin.com/in/harisekhon
#

# ===================
# bootstrap commands:

# setup/bootstrap.sh
#
# OR
#
# Alpine:
#
#   apk add --no-cache git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make
#
# Debian / Ubuntu:
#
#   apt-get update && apt-get install -y git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make
#
# RHEL / CentOS:
#
#   yum install -y git make && git clone https://github.com/harisekhon/nagios-plugins && cd nagios-plugins && make

# ===================

ifneq ("$(wildcard bash-tools/Makefile.in)", "")
	include bash-tools/Makefile.in
endif

REPO := HariSekhon/Nagios-Plugins

# cannot differentiate symlinks which I want to ignore even if committed as it hyperinflates the code counts
#CODE_FILES := $(shell git ls-files | grep -Ee '\.py$$' -e '\.pl$$' -e '\.sh$$' -e '\.wsf$$' | grep -Ev -e bash-tools -e /lib/ -e /pylib/ -e TODO)
CODE_FILES := $(shell find . -type f -name '*.py' -o -type f -name '*.pl' -o -type f -name '*.sh' -o -type f -name '*.wsf' | grep -Eve bash-tools -e /lib/ -e /pylib/ -e TODO -e '/zookeeper-[[:digit:]]+\.[[:digit:]]+\.[[:digit:]]+/' -e /fatpacks/)

DOCKER_IMAGE := harisekhon/nagios-plugins

ifndef CPANM
	CPANM := cpanm
endif

# tested, this works
.PHONY: *

.PHONY: build
# space here prevents weird validation warning from check_makefile.sh => Makefile:40: warning: undefined variable `D'
build : init
	@echo ====================
	@echo Nagios Plugins Build
	@echo ====================
	@$(MAKE) git-summary

	@# doesn't exit Make anyway, just line, and don't wanna use oneshell
	@# doubles build time
	@#if [ -z "$(CPANM)" ]; then $(MAKE); exit $$?; fi
	$(MAKE) perl
	$(MAKE) python
	@echo
	#$(MAKE) jar-plugins
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins)"

.PHONY: init
init:
	git submodule update --init --recursive

.PHONY: perl
perl : init
	@echo ===========================
	@echo "Nagios Plugins Build (Perl)"
	@echo ===========================

	@# doesn't exit Make anyway, just line, and don't wanna use oneshell
	@# doubles build time
	@#if [ -z "$(CPANM)" ]; then $(MAKE) perl; exit $$?; fi
	$(MAKE) system-packages-perl
	$(MAKE) perl-libs
	$(MAKE) zookeeper

.PHONY: perl-libs
perl-libs:
	cd lib && make build test

	# XXX: there is a bug in the Readonly module that MongoDB::MongoClient uses. It tries to call Readonly::XS but there is some kind of MAGIC_COOKIE mismatch and Readonly::XS errors out with:
	#
	# Readonly::XS is not a standalone module. You should not use it directly. at /usr/local/lib64/perl5/Readonly/XS.pm line 34.
	#
	# Workaround is to edit Readonly.pm and comment out line 33 which does the eval 'use Readonly::XS';
	# On Linux this is located at:
	#
	# /usr/local/share/perl5/Readonly.pm
	#
	# On my Mac OS X Mavericks:
	#
	# /Library/Perl/5.16/Readonly.pm

	# Required to successfully build the MongoDB module for For RHEL 5
	#sudo cpan Attribute::Handlers
	#sudo cpan Params::Validate
	#sudo cpan DateTime::Locale DateTime::TimeZone
	#sudo cpan DateTime

	# You may need to set this to get the DBD::mysql module to install if you have mysql installed locally to /usr/local/mysql
	#export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:/usr/local/mysql/lib/"

	setup/install_mysql_perl.sh

	bash-tools/perl_cpanm_install_if_absent.sh setup/cpan-requirements.txt setup/cpan-requirements-packaged.txt

	# to work around "Can't locate loadable object for module Digest::CRC in @INC"
	@. bash-tools/lib/ci.sh; \
		. bash-tools/lib/os.sh; \
		if is_CI and is_mac; then \
			bash-tools/perl_cpanm_install.sh Digest::CRC; \
		fi

	# packaged version is not new enough:
	# ./check_mongodb_master.pl:  CRITICAL: IO::Socket::IP version 0.32 required--this is only version 0.21 at /usr/local/share/perl5/MongoDB/_Link.pm line 53.
	bash-tools/perl_cpanm_install.sh IO::Socket::IP

	setup/fix_perl_netaddr_ip_inetbase.sh

	setup/mac_symlink_nagios_plugins_libexec.sh

	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins perl)"
	@echo
	@echo

.PHONY: fatpacks-local
fatpacks-local:
	setup/fix_perl_netaddr_ip_inetbase.sh

.PHONY: python
python: init
	@echo =============================
	@echo "Nagios Plugins Build (Python)"
	@echo =============================

	@# doesn't exit Make anyway, just line, and don't wanna use oneshell
	@# doubles build time
	@#if [ -z "$(CPANM)" ]; then $(MAKE) python; exit $$?; fi
	$(MAKE) system-packages-python
	$(MAKE) python-libs

.PHONY: python-libs
python-libs:
	cd pylib && make build test

	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	#$(SUDO) easy_install -U setuptools || $(SUDO_PIP) easy_install -U setuptools || :
	#$(SUDO) easy_install pip || :

	# fixes bug in cffi version detection when installing requests-kerberos
	$(SUDO_PIP) pip install --quiet --upgrade pip
	# on Travis CI /opt/pyenv/shims/pip: Could not install packages due to an EnvironmentError: [Errno 13] Permission denied: '/usr/bin/pip'
	#PIP_OPTS="--quiet --upgrade" bash-tools/python_pip_install.sh pip

	setup/install_mysql_python.sh

	# only install pip packages not installed via system packages
	#$(SUDO_PIP) pip install --quiet --upgrade -r requirements.txt
	#$(SUDO_PIP) pip install --quiet -r requirements.txt
	bash-tools/python_pip_install_if_absent.sh requirements.txt

	@echo "forcing Pika PyPI module version install because of Python 3.7 compatibility issue"
	PIP_OPTS="--upgrade" bash-tools/python_pip_install.sh `sed 's/^#.*//' requirements.txt | grep ^pika==`

	@# python-krbV dependency doesn't build on Mac any more and is unmaintained and not ported to Python 3
	@# python_pip_install_if_absent.sh would import snakebite module and not trigger to build the enhanced snakebite with [kerberos] bit
	bash-tools/setup/python_install_snakebite.sh

	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	# in requirements.txt now
	#$(SUDO_PIP) pip install --quiet cassandra-driver scales blist lz4 python-snappy

	# prevents https://urllib3.readthedocs.io/en/latest/security.html#insecureplatformwarning
	#$(SUDO_PIP) pip install --quiet --upgrade ndg-httpsclient || \
	#$(SUDO_PIP) pip install --quiet --upgrade ndg-httpsclient
	PIP_OPTS="--quiet --upgrade" bash-tools/python_pip_install.sh ndg-httpsclient || \
	PIP_OPTS="--quiet --upgrade" bash-tools/python_pip_install.sh ndg-httpsclient

	#. tests/utils.sh; $(SUDO) $$perl couchbase-csdk-setup
	#$(SUDO_PIP) pip install --quiet couchbase

	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	# Mac fails to import module, one workaround is:
	# sudo install_name_tool -change libmysqlclient.18.dylib /usr/local/mysql/lib/libmysqlclient.18.dylib /Library/Python/2.7/site-packages/_mysql.so
	# in requirements.txt now
	#$(SUDO_PIP) pip install --quiet MySQL-python

	# must downgrade happybase library to work on Python 2.6
	setup/python2.6_happybase_downgrade.sh

	@echo
	unalias mv 2>/dev/null; \
	for x in $$(curl -s https://api.github.com/repos/harisekhon/devops-python-tools/contents | jq '.[].name' | sed 's/"//g' | grep '^find_active_.*.py' ); do \
		wget -qO $$x.tmp https://raw.githubusercontent.com/HariSekhon/devops-python-tools/master/$$x && \
		mv -vf $$x.tmp $$x; \
		chmod +x $$x; \
	done
	@echo
	$(MAKE) pycompile
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins python)"
	@echo
	@echo

# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
# doesn't build on Mac < 3.4.7 / 3.5.1 / 3.6.0 but the others are in the public mirrors yet
# https://issues.apache.org/jira/browse/ZOOKEEPER-2049
ZOOKEEPER_VERSION = 3.4.12
.PHONY: zookeeper
zookeeper : perl zkperl
	@:

.PHONY: zookeeper-retry
zookeeper-retry:
	bash-tools/retry.sh $(MAKE) zookeeper

.PHONY: zkperl
zkperl:
	ZOOKEEPER_VERSION="$(ZOOKEEPER_VERSION)" setup/install_zookeeper_perl.sh
	@echo
	@echo "BUILD SUCCESSFUL (nagios-plugins zkperl)"
	@echo
	@echo

.PHONY: jar-plugins
jar-plugins:
	@echo Fetching pre-compiled Java / Scala plugins
	@echo
	@echo Fetching Kafka Scala Nagios Plugin
	@echo fetching jar wrapper shell script
	# if removing and re-uploading latest this would get 404 and exit immediately without the rest of the retries
	#wget -c -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka
	for x in {1..6}; do wget -qc https://github.com/HariSekhon/nagios-plugin-kafka/blob/latest/check_kafka && break; sleep 10; done
	@echo fetching jar
	#wget -qc -t 5 --retry-connrefused https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar
	for x in {1..6}; do wget -qc https://github.com/HariSekhon/nagios-plugin-kafka/releases/download/latest/check_kafka.jar && break; sleep 10; done

.PHONY: lib-test
lib-test:
	cd lib && $(MAKE) test
	rm -fr lib/cover_db || :
	cd pylib && $(MAKE) test

.PHONY: test
test: lib-test
	tests/all.sh

.PHONY: basic-test
basic-test: lib-test
	. tests/excluded.sh; bash-tools/check_all.sh
	tests/help.sh

.PHONY: install
install : build
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: clean
clean:
	cd lib && $(MAKE) clean
	cd pylib && $(MAKE) clean
	@find . -maxdepth 3 -iname '*.py[co]' -o -iname '*.jy[co]' | xargs rm -f || :
	@find . -iname '*.spec' | xargs rm -f
	@$(MAKE) clean-zookeeper
	rm -fr tests/spark-*-bin-hadoop*

.PHONY: clean-zookeeper
clean-zookeeper:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)

.PHONY: deep-clean
deep-clean: clean clean-zookeeper
	cd lib && $(MAKE) deep-clean
	cd pylib && $(MAKE) deep-clean

.PHONY: dockerhub-trigger
dockerhub-trigger:
	# Nagios Plugins
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/867fff52-9a87-4ca2-84e5-62603473083f/trigger/5b0d1a59-8b53-466a-87d7-8e99dfd01f16/call/
	# Alpine Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/df816f2a-9407-4f1b-8b51-39615d784e65/trigger/8d9cb826-48df-439c-8c20-1975713064fc/call/
	# CentOS Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/efba1846-5a9e-470a-92f8-69edc1232ba0/trigger/316d1158-7ffb-49a4-a7bd-8e5456ba2d15/call/
	# Debian Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/439eff84-50c7-464a-a49e-0ac0bf1a9a43/trigger/0cfb3fe7-2028-494b-a43b-068435e6a2b3/call/
	# Fedora Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/7170c9dc-10b5-42b8-9df9-f1ea830cc32f/trigger/e0648979-3bf6-48f0-89c9-486588d2e657/call/
	# Ubuntu Github
	curl --header "Content:Type:application/json" --data '{"build":true}' -X POST https://cloud.docker.com/api/build/v1/source/8b3dc094-d4ca-4c92-861e-1e842b5fac42/trigger/abd4dbf0-14bc-454f-9cde-081ec014bc48/call/
