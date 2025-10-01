FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20250921101147-b4280839 as build-image

USER root

# Set up working directories
WORKDIR /app
COPY . /app

RUN pip3.11 install --no-cache-dir -r requirements-dev.txt
# hadolint ignore=DL3059
RUN python3.11 -m unittest

FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/container-base-2023:20250918101340-3e7bff99 as clamav-image

USER root

# Install packages and build dependencies
RUN dnf install -y cpio less wget gcc make pkgconfig zlib-devel bzip2-devel check-devel libtool-ltdl-devel

# Create directories for ClamAV
WORKDIR /tmp
RUN mkdir -p /clamav/bin /clamav/lib

# Get architecture and download appropriate ClamAV RPM - version 1.4.3
RUN ARCH=$(uname -m) && \
    if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then \
        echo "Detected ARM64 architecture, using aarch64 package" && \
        wget -O /tmp/clamav.rpm https://www.clamav.net/downloads/production/clamav-1.4.3.linux.aarch64.rpm; \
    else \
        echo "Detected x86_64 architecture, using x86_64 package" && \
        wget -O /tmp/clamav.rpm https://www.clamav.net/downloads/production/clamav-1.4.3.linux.x86_64.rpm; \
    fi && \
    mkdir -p /tmp/clamav_extract && \
    cd /tmp/clamav_extract && \
    rpm2cpio /tmp/clamav.rpm | cpio -idmv && \
    cp usr/local/bin/clamscan /clamav/bin/ && \
    cp usr/local/bin/freshclam /clamav/bin/ && \
    # Copy all library files including the specific libfreshclam.so.3
    cp -r usr/local/lib64/* /clamav/lib/ && \
    # Debug to see what libraries are available
    find usr -name "*.so*" && \
    # Copy specific libraries that might be in a different location
    find usr -name "libfreshclam.so*" -exec cp {} /clamav/lib/ \; && \
    chmod +x /clamav/bin/clamscan /clamav/bin/freshclam && \
    rm -rf /tmp/clamav.rpm

# Download system dependencies
WORKDIR /var/cache/dnf
RUN dnf download json-c pcre2 pcre libprelude gnutls libtasn1 nettle openssl-libs

# Extract system packages
RUN rpm2cpio json-c*.rpm | cpio -idmv || true
RUN rpm2cpio pcre-*.rpm | cpio -idmv || true
RUN rpm2cpio pcre2-*.rpm | cpio -idmv || true
RUN rpm2cpio gnutls*.rpm | cpio -idmv || true
RUN rpm2cpio libtasn1*.rpm | cpio -idmv || true
RUN rpm2cpio nettle*.rpm | cpio -idmv || true
RUN rpm2cpio openssl*.rpm | cpio -idmv || true

# Copy needed libraries
RUN cp -r /var/cache/dnf/usr/lib64/* /clamav/lib/ || true
# Check what libraries we're working with for debugging
RUN ls -la /clamav/lib/ | grep -i clam || echo "No clamav libraries found in extracted directory"

# Fix the freshclam.conf settings for ClamAV 1.4.3
RUN echo "DatabaseMirror database.clamav.net" > /clamav/freshclam.conf && \
    echo "CompressLocalDatabase yes" >> /clamav/freshclam.conf && \
    echo "ScriptedUpdates yes" >> /clamav/freshclam.conf && \
    echo "Bytecode yes" >> /clamav/freshclam.conf && \
    echo "DNSDatabaseInfo current.cvd.clamav.net" >> /clamav/freshclam.conf && \
    echo "ConnectTimeout 60" >> /clamav/freshclam.conf && \
    echo "ReceiveTimeout 60" >> /clamav/freshclam.conf && \
    echo "DatabaseOwner root" >> /clamav/freshclam.conf && \
    echo "DatabaseDirectory /tmp/clamav" >> /clamav/freshclam.conf


FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20250921101147-b4280839

USER root

RUN dnf install -y libtool-ltdl binutils findutils

WORKDIR /var/task

# Copy all dependencies from previous layers
COPY --chown=upgrade:upgrade --from=build-image /app/*.py /var/task
COPY --chown=upgrade:upgrade --from=build-image /app/requirements.txt /var/task/requirements.txt
COPY --chown=upgrade:upgrade --from=build-image /app/custom_clamav_rules /var/task/bin/custom_clamav_rules
COPY --chown=upgrade:upgrade --from=clamav-image /clamav /var/task

# Loading all shared libraries
RUN mkdir -p /var/task/lib
# Copy binaries and libraries to the lib directory
RUN cp /var/task/bin/* /var/task/lib/ || true
# Ensure all libraries from lib are properly copied (might have subdirectories)
RUN find /var/task/lib -type f -name "*.so*" -exec cp {} /var/task/lib/ \; || true
# Set the library path to include both /var/task/lib and standard library paths
ENV LD_LIBRARY_PATH=/var/task/lib:/usr/lib64:/usr/local/lib64
# Update the dynamic linker run-time bindings
RUN ldconfig
# Create necessary symlinks directly
RUN echo "Checking for required libraries in /var/task/lib" && \
    ls -la /var/task/lib/ | grep -i "freshclam\|clam" && \
    echo "Creating symlinks for required libraries" && \
    ln -sf /var/task/lib/libfreshclam.so.3.0.2 /var/task/lib/libfreshclam.so.3 && \
    ln -sf /var/task/lib/libclamav.so.12.0.3 /var/task/lib/libclamav.so.9 && \
    ln -sf /var/task/lib/libclammspack.so.0.8.0 /var/task/lib/libclammspack.so.0 && \
    echo "Verifying ClamAV binary compatibility" && \
    /var/task/bin/clamscan --version

# Test running freshclam with proper library path
RUN echo "Testing freshclam execution with correct library path" && \
    mkdir -p /tmp/clamav && \
    cd /var/task && \
    echo "Making freshclam executable" && \
    chmod +x /var/task/bin/freshclam && \
    echo "Verifying freshclam version" && \
    LD_LIBRARY_PATH=/var/task/lib:/usr/lib64:/usr/local/lib64 /var/task/bin/freshclam --config-file=/var/task/freshclam.conf --version || \
    echo "Warning: freshclam version check failed"

RUN pip3.11 install --no-cache-dir -r requirements.txt --target /var/task awslambdaric

ENTRYPOINT [ "python3.11", "-m", "awslambdaric" ]
