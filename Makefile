#
#  Author: Hari Sekhon
#  Date: 2013-02-03 10:25:36 +0000 (Sun, 03 Feb 2013)
#

.PHONY: make
make install:
	@ [ $$EUID -eq 0 ] || { echo "error: must be root to install cpan modules"; exit 1; }
	cpan DBD::mysql
	cpan DBI
	cpan LWP::Simple
	cpan LWP::UserAgent
	cpan Net::DNS
	cpan Net::SSH::Expect
	cpan SMS::AQL
	git submodule init
	git sudmodule update
