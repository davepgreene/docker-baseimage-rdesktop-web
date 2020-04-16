FROM lsiobase/ubuntu:bionic as builder

ARG GUACD_VERSION=1.1.0

COPY /buildroot /

RUN \
 echo "**** install build deps ****" && \
 apt-get update && \
 apt-get install -qy --no-install-recommends \
	autoconf \
	automake \
	checkinstall \
	freerdp2-dev \
	g++ \
	gcc \
	git \
	libavcodec-dev \
	libavutil-dev \
	libcairo2-dev \
	libjpeg-turbo8-dev \
	libogg-dev \
	libossp-uuid-dev \
	libpulse-dev \
	libssl-dev \
	libswscale-dev \
	libtool \
	libvorbis-dev \
	libwebsockets-dev \
	libwebp-dev \
	make

RUN \
 echo "**** prep build ****" && \
 mkdir /tmp/guacd && \
 git clone https://github.com/apache/guacamole-server.git /tmp/guacd && \
 echo "**** build guacd ****" && \
 cd /tmp/guacd && \
 git checkout ${GUACD_VERSION} && \
 autoreconf -fi && \
 ./configure --prefix=/usr && \
 make -j 2 && \
 mkdir -p /tmp/out && \
 /usr/bin/list-dependencies.sh \
	"/tmp/guacd/src/guacd/.libs/guacd" \
	$(find /tmp/guacd | grep "so$") \
	> /tmp/out/DEPENDENCIES && \
 PREFIX=/usr checkinstall \
	-y \
	-D \
	--nodoc \
	--pkgname guacd \
	--pkgversion "${GUACD_VERSION}" \
	--pakdir /tmp \
	--exclude "/usr/share/man","/usr/include","/etc" && \
 mkdir -p /tmp/out && \
 mv \
	/tmp/guacd_${GUACD_VERSION}-*.deb \
	/tmp/out/guacd_${GUACD_VERSION}.deb

# runtime stage
FROM lsiobase/rdesktop:bionic

# set version label
ARG BUILD_DATE
ARG VERSION
ARG GUACD_VERSION=1.1.0
ARG TOMCAT_VER=tomcat9
ENV TOMCAT_VER=${TOMCAT_VER}
LABEL build_version="Linuxserver.io version:- ${VERSION} Build-date:- ${BUILD_DATE}"
LABEL maintainer="thelamer"

# Copy build outputs
COPY --from=builder /tmp/out /tmp/out

RUN \
 echo "**** install guacd ****" && \
 dpkg --path-include=/usr/share/doc/${PKG_NAME}/* \
        -i /tmp/out/guacd_${GUACD_VERSION}.deb && \
 echo "**** install packages ****" && \
 apt-get update && \
 DEBIAN_FRONTEND=noninteractive \
 apt-get install --no-install-recommends -y \
	ca-certificates \
	libfreerdp2-2 \
	libfreerdp-client2-2 \
	libjna-java \
	libossp-uuid16 \
	obconf \
	openbox \
	python \
	${TOMCAT_VER} \
	${TOMCAT_VER}-common \
	${TOMCAT_VER}-user \
	xterm && \
 apt-get install -qy --no-install-recommends \
	$(cat /tmp/out/DEPENDENCIES) && \
 echo "**** install guacamole ****" && \
 mkdir -p \
	/etc/guacamole/extensions \
	/etc/guacamole/lib && \
 curl -o /etc/guacamole/guacamole.war \
	-L http://archive.apache.org/dist/guacamole/${GUACD_VERSION}/binary/guacamole-${GUACD_VERSION}.war && \
 echo "GUACAMOLE_HOME=/etc/guacamole" >> /etc/default/${TOMCAT_VER} && \
 ln -s /etc/guacamole /usr/share/${TOMCAT_VER}/.guacamole && \
 usermod -a -G shadow tomcat && \
 rm -Rf /var/lib/${TOMCAT_VER}/webapps/ROOT && \
 curl -o /etc/guacamole/extensions/guacamole-auth-pam.jar \
	-L https://github.com/voegelas/guacamole-auth-pam/releases/download/v1.4/guacamole-auth-pam-1.0.0.jar && \
 chown -R tomcat:tomcat /var/lib/tomcat9/ && \
 curl -o /tmp/libpam.deb \
	-L "http://security.ubuntu.com/ubuntu/pool/universe/libp/libpam4j/libpam4j-java_1.4-2+deb8u1build0.16.04.1_all.deb" && \
 dpkg -i /tmp/libpam.deb && \
 echo "**** cleanup ****" && \
 mv /usr/bin/passwd /usr/bin/passwdbin && \
 apt-get autoclean && \
 rm -rf \
        /var/lib/apt/lists/* \
        /var/tmp/* \
        /tmp/*

# add local files
COPY /root /

# ports and volumes
EXPOSE 8080
VOLUME /config
