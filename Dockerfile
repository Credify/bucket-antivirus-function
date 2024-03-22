FROM public.ecr.aws/lambda/python:3.8 as build-image

# Set up working directories
WORKDIR /app
COPY . /app

RUN pip3 install --no-cache-dir -r requirements-dev.txt
# hadolint ignore=DL3059
RUN python3 -m unittest

FROM docker-release.artifactory.build.upgrade.com/container-base-2023:2.0.20240306.2-76 as clamav-image

USER root

# Install packages
RUN dnf install -y cpio less
#RUN dnf install -y https://dl.fedoraproject.org/pub/epel/epel-release-latest-7.noarch.rpm

# Download libraries we need to run in lambda
WORKDIR /var/cache/dnf
RUN dnf download --archlist=x86_64 clamav clamav-lib clamav-update json-c pcre2 pcre libprelude gnutls libtasn1 nettle

RUN rpm2cpio clamav*.rpm | cpio -idmv
RUN rpm2cpio clamav-lib*.rpm | cpio -idmv
RUN rpm2cpio clamav-update*.rpm | cpio -idmv
RUN rpm2cpio json-c*.rpm | cpio -idmv
RUN rpm2cpio pcre*.rpm | cpio -idmv
RUN rpm2cpio gnutls*.rpm | cpio -idmv
RUN rpm2cpio libtasn1*.rpm | cpio -idmv
RUN rpm2cpio nettle*.rpm | cpio -idmv

# Copy over the binaries and libraries
WORKDIR /tmp
RUN mkdir /clamav
RUN cp /var/cache/dnf/usr/bin/clamscan /var/cache/dnf/usr/bin/freshclam /var/cache/dnf/usr/lib64/* /clamav

# Fix the freshclam.conf settings
RUN echo "DatabaseMirror database.clamav.net" > /clamav/freshclam.conf && \
    echo "CompressLocalDatabase yes" >> /clamav/freshclam.conf

FROM public.ecr.aws/lambda/python:3.8

RUN yum install -y libtool-ltdl binutils

WORKDIR /var/task

# Copy all dependencies from previous layers
COPY --chown=upgrade:upgrade --from=build-image /app/*.py /var/task
COPY --chown=upgrade:upgrade --from=build-image /app/requirements.txt /var/task/requirements.txt
COPY --chown=upgrade:upgrade --from=build-image /app/custom_clamav_rules /var/task/bin/custom_clamav_rules
COPY --chown=upgrade:upgrade --from=clamav-image /clamav /var/task/bin

RUN pip3 install --no-cache-dir -r requirements.txt --target /var/task
