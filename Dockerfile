#Stage 1 : builder debian image
FROM debian:bulleye as builder

# properly setup debian sources
ENV DEBIAN_FRONTEND noninteractive

# install package building helpers
# rsyslog for logging (ref https://github.com/stilliard/docker-pure-ftpd/issues/17)
RUN apt-get -y update && \
	apt-get -y --force-yes --fix-missing install dpkg-dev debhelper &&\
	apt-get -y build-dep pure-ftpd

# Build from source - we need to remove the need for CAP_SYS_NICE and CAP_DAC_READ_SEARCH
RUN mkdir /tmp/pure-ftpd/ && \
	cd /tmp/pure-ftpd/ && \
	apt-get source pure-ftpd && \
	cd pure-ftpd-* && \
	./configure --with-tls | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory' && \
	sed -i '/CAP_SYS_NICE,/d; /CAP_DAC_READ_SEARCH/d; s/CAP_SYS_CHROOT,/CAP_SYS_CHROOT/;' src/caps_p.h && \
	dpkg-buildpackage -b -uc | grep -v '^checking' | grep -v ': Entering directory' | grep -v ': Leaving directory'

#Stage 2 : actual pure-ftpd image
FROM debian:bulleye-slim

LABEL maintainer "Kevin Wang <kevixw@gmail.com>"

# install dependencies
# FIXME : libcap2 is not a dependency anymore. .deb could be fixed to avoid asking this dependency
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get -y update && \
	apt-get --no-install-recommends --yes install \
	libc6 \
	libcap2 \
    	libmariadb3 \
	libpam0g \
	libssl1.1 \
    	lsb-base \
    	openbsd-inetd \
    	openssl \
    	perl \
	rsyslog

COPY --from=builder /tmp/pure-ftpd/*.deb /tmp/pure-ftpd/

# setup run/init file
COPY run.sh /run.sh

# install the new deb files
RUN dpkg -i /tmp/pure-ftpd/pure-ftpd-common*.deb && \
	dpkg -i /tmp/pure-ftpd/pure-ftpd_*.deb && \
	# dpkg -i /tmp/pure-ftpd/pure-ftpd-ldap_*.deb && \
	# dpkg -i /tmp/pure-ftpd/pure-ftpd-mysql_*.deb && \
	# dpkg -i /tmp/pure-ftpd/pure-ftpd-postgresql_*.deb && \
	rm -Rf /tmp/pure-ftpd && \
	apt-mark hold pure-ftpd pure-ftpd-common && \
	apt-get -y clean && \
	apt-get -y autoclean && \
	apt-get -y autoremove && \
	rm -rf /var/lib/apt/lists/* && \
	groupadd ftpgroup && \
	useradd -g ftpgroup -d /home/ftpusers -s /dev/null ftpuser && \
	echo "" >> /etc/rsyslog.conf && \
	echo "#PureFTP Custom Logging" >> /etc/rsyslog.conf && \
	echo "ftp.* /var/log/pure-ftpd/pureftpd.log" >> /etc/rsyslog.conf && \
	echo "Updated /etc/rsyslog.conf with /var/log/pure-ftpd/pureftpd.log" && \
	chmod u+x /run.sh

# default publichost, you'll need to set this for passive support
ENV PUBLICHOST localhost

# couple available volumes you may want to use
VOLUME ["/home/ftpusers", "/etc/pure-ftpd/passwd"]

# startup
CMD /run.sh -l puredb:/etc/pure-ftpd/pureftpd.pdb -E -j -R -P $PUBLICHOST

EXPOSE 21 30000-30009
