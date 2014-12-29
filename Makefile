#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#
#  http://github.com/harisekhon
#

.PHONY: make
make:
	[ -x /usr/bin/apt-get ] && make apt-packages || :
	[ -x /usr/bin/yum ]     && make yum-packages || :
	
	git submodule init
	git submodule update

	cd lib && make

	# There are problems with the tests for this module dependency of Net::Async::CassandraCQL, forcing install works and allows us to use check_cassandra_write.pl
	#sudo cpan -f IO::Async::Stream

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

	# TODO: check LWP::Authen::Negotiate with webhdfs against Kerberized cluster
	
	# You may need to set this to get the DBD::mysql module to install if you have mysql installed locally to /usr/local/mysql
	#export DYLD_LIBRARY_PATH="$DYLD_LIBRARY_PATH:/usr/local/mysql/lib/"

	@#@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	@# putting modules one per line just for ease of maintenance
	#
	# add -E to sudo to preserve http proxy env vars or run this manually if needed (only works on Mac)
	yes | sudo cpan \
		Class:Accessor \
		Data::Dumper \
		DBD::mysql \
		DBI \
		Digest::SHA \
		IO::Socket::SSL \
		JSON \
		JSON:XS \
		LWP::Authen::Negotiate \
		LWP::Simple \
		LWP::UserAgent \
		MongoDB \
		MongoDB::MongoClient \
		Net::LDAP \
		Net::LDAPI \
		Net::LDAPS \
		Net::DNS \
		Net::SSH::Expect \
		Redis \
		Readonly \
		Readonly::XS \
		Test::SharedFork \
		Thrift \
		Time::HiRes \
		Type::Tiny::XS \
		SMS::AQL \
		URI::Escape \
		XML::Simple \
		; echo
		#Net::Async::CassandraCQL \
	# Intentionally ignoring CPAN module build failures since some modules may fail for a multitude of reasons but this isn't really important unless you need the pieces of code that use them in which case you can solve those dependencies later
	
	# newer version of setuptools (>=0.9.6) is needed to install cassandra-driver
	# might need to specify /usr/bin/easy_install or make /usr/bin first in path as sometimes there are version conflicts with Python's easy_install
	easy_install -U setuptools || :
	sudo easy_install pip || :
	# cassandra-driver is needed for check_cassandra_write.py + check_cassandra_query.py
	sudo pip install cassandra-driver scales blist lz4 python-snappy || :
	
	# install MySQLdb python module for check_logserver.py / check_syslog_mysql.py
	# fails if MySQL isn't installed locally
	#sudo pip install MySQLdb


.PHONY: apt-packages
apt-packages:
	# needed to fetch and build CPAN modules and fetch the library submodule at end of build
	apt-get install -y build-essential libwww-perl git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN
	apt-get install -y libdbd-mysql-perl libmysqlclient-dev || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	apt-get install -y libssl-dev || :
	# for XML::Simple building
	apt-get install -y libexpat1-dev || :
	# for check_whois.pl
	apt-get install -y jwhois || :
	# TODO: for LWP::Authenticate - prompts for realm + KDC, doesn't seem automatable and not properly tested yet
	#apt-get install -y krb5-config || :
	# for Cassandra's Python driver
	apt-get install -y python-setuptools python-dev libev4 libev-dev libsnappy-dev || :

.PHONY: yum-packages
yum-packages:
	# needed to fetch and build CPAN modules and fetch the library submodule at end of build
	yum install -y gcc perl-CPAN perl-libwww-perl git || :
	# for DBD::mysql as well as headers to build DBD::mysql if building from CPAN
	yum install -y perl-DBD-MySQL mysql-devel || :
	# needed to build Net::SSLeay for IO::Socket::SSL for Net::LDAPS
	yum install -y openssl-devel || :
	# for XML::Simple building
	yum install -y expat-devel || :
	# for check_whois.pl
	yum install -y jwhois || :
	# for Cassandra's Python driver
	yum install -y python-setuptools python-devel libev libev-devel libsnappy-devel || :


# Net::ZooKeeper must be done separately due to the C library dependency it fails when attempting to install directly from CPAN. You will also need Net::ZooKeeper for check_zookeeper_znode.pl to be, see README.md or instructions at https://github.com/harisekhon/nagios-plugins
ZOOKEEPER_VERSION = 3.4.5
.PHONY: zookeeper
zookeeper:
	[ -f zookeeper-$(ZOOKEEPER_VERSION).tar.gz ] || wget -O zookeeper-$(ZOOKEEPER_VERSION).tar.gz http://www.mirrorservice.org/sites/ftp.apache.org/zookeeper/zookeeper-$(ZOOKEEPER_VERSION)/zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	[ -d zookeeper-$(ZOOKEEPER_VERSION) ] || tar zxvf zookeeper-$(ZOOKEEPER_VERSION).tar.gz
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				./configure
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/c; 				sudo make install
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	perl Makefile.PL --zookeeper-include=/usr/local/include/zookeeper --zookeeper-lib=/usr/local/lib
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	LD_RUN_PATH=/usr/local/lib make
	cd zookeeper-$(ZOOKEEPER_VERSION)/src/contrib/zkperl; 	sudo make install
	perl -e "use Net::ZooKeeper"


.PHONY: test
test:
	cd lib && make test
	# TODO: add my functional tests back in here	

.PHONY: install
install:
	@echo "No installation needed, just add '$(PWD)' to your \$$PATH and Nagios commands.cfg"

.PHONY: update
update:
	make update2
	make
	make test

.PHONY: update2
update2:
	git pull
	git submodule update

.PHONY: clean
clean:
	rm -fr zookeeper-$(ZOOKEEPER_VERSION).tar.gz zookeeper-$(ZOOKEEPER_VERSION)
