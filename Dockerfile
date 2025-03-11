FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20250310100934-fec7cfd6 as build-image

USER root

# Set up working directories
WORKDIR /app
COPY . /app

RUN pip3.11 install --no-cache-dir -r requirements-dev.txt
# hadolint ignore=DL3059
RUN python3.11 -m unittest

FROM docker-release.artifactory.build.upgrade.com/container-base-2023:2.0.20250305.0-19 as clamav-image

USER root

# Install packages
RUN dnf install -y cpio less

# Download libraries we need to run in lambda
WORKDIR /var/cache/dnf
RUN dnf download --archlist=x86_64 clamav clamav-lib clamav-update json-c pcre2 pcre libprelude gnutls libtasn1 nettle openssl-libs

RUN rpm2cpio clamav*.rpm | cpio -idmv
RUN rpm2cpio clamav-lib*.rpm | cpio -idmv
RUN rpm2cpio lib* | cpio -idmv
RUN rpm2cpio clamav-update*.rpm | cpio -idmv
RUN rpm2cpio json-c*.rpm | cpio -idmv
RUN rpm2cpio pcre-*.rpm | cpio -idmv
RUN rpm2cpio pcre2-*.rpm | cpio -idmv
RUN rpm2cpio gnutls*.rpm | cpio -idmv
RUN rpm2cpio libtasn1*.rpm | cpio -idmv
RUN rpm2cpio nettle*.rpm | cpio -idmv
RUN rpm2cpio openssl*.rpm | cpio -idmv

# Copy over the binaries and libraries
WORKDIR /tmp
RUN mkdir /clamav
RUN cp /var/cache/dnf/usr/bin/clamscan /var/cache/dnf/usr/bin/freshclam /var/cache/dnf/usr/lib64/* /clamav -r

# Fix the freshclam.conf settings
RUN echo "DatabaseMirror database.clamav.net" > /clamav/freshclam.conf && \
    echo "CompressLocalDatabase yes" >> /clamav/freshclam.conf


FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20250310100934-fec7cfd6

USER root

RUN dnf install -y libtool-ltdl binutils

WORKDIR /var/task

# Copy all dependencies from previous layers
COPY --chown=upgrade:upgrade --from=build-image /app/*.py /var/task
COPY --chown=upgrade:upgrade --from=build-image /app/requirements.txt /var/task/requirements.txt
COPY --chown=upgrade:upgrade --from=build-image /app/custom_clamav_rules /var/task/bin/custom_clamav_rules
COPY --chown=upgrade:upgrade --from=clamav-image /clamav /var/task/bin

# Loading all shared libraries
RUN mkdir /var/task/lib
RUN cp /var/task/bin/* /var/task/lib -r
ENV LD_LIBRARY_PATH=/var/task/lib
RUN ldconfig

RUN pip3.11 install --no-cache-dir -r requirements.txt --target /var/task awslambdaric

ENTRYPOINT [ "python3.11", "-m", "awslambdaric" ]
