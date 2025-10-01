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
    CLAMAV_URL=$([ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ] && \
                echo "https://www.clamav.net/downloads/production/clamav-1.4.3.linux.aarch64.rpm" || \
                echo "https://www.clamav.net/downloads/production/clamav-1.4.3.linux.x86_64.rpm") && \
    wget -O /tmp/clamav.rpm $CLAMAV_URL && \
    mkdir -p /tmp/clamav_extract && \
    cd /tmp/clamav_extract && \
    rpm2cpio /tmp/clamav.rpm | cpio -idmv && \
    # Copy binaries and libraries
    cp usr/local/bin/clamscan /clamav/bin/ && \
    cp usr/local/bin/freshclam /clamav/bin/ && \
    cp -r usr/local/lib64/* /clamav/lib/ && \
    find usr -name "libfreshclam.so*" -exec cp {} /clamav/lib/ \; && \
    chmod +x /clamav/bin/clamscan /clamav/bin/freshclam && \
    # Cleanup
    rm -rf /tmp/clamav.rpm /tmp/clamav_extract

# Download and extract system dependencies in one step
WORKDIR /var/cache/dnf
RUN dnf download json-c pcre2 pcre libprelude gnutls libtasn1 nettle openssl-libs && \
    mkdir -p /var/cache/dnf/extracted && \
    # Extract all packages
    for pkg in *.rpm; do \
        rpm2cpio $pkg | cpio -idmv -D /var/cache/dnf/extracted 2>/dev/null || true; \
    done && \
    # Copy needed libraries
    cp -r /var/cache/dnf/extracted/usr/lib64/* /clamav/lib/ 2>/dev/null || true && \
    # Cleanup
    rm -rf /var/cache/dnf/*.rpm /var/cache/dnf/extracted

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
COPY --from=clamav-image /clamav /var/task

# Set up permissions and libraries
RUN mkdir -p /var/task/lib && \
    # Copy all libraries to the lib directory
    cp /var/task/bin/freshclam /var/task/bin/clamscan /var/task/lib/ 2>/dev/null || true && \
    find /var/task -type f -name "*.so*" -exec cp {} /var/task/lib/ \; 2>/dev/null || true && \
    # Fix permissions for Lambda execution
    chmod -R 755 /var/task/bin && \
    chmod 644 /var/task/*.py && \
    chmod 755 /var/task/bin/freshclam /var/task/bin/clamscan /var/task/lib/freshclam /var/task/lib/clamscan && \
    chown -R upgrade:upgrade /var/task && \
    # Update the dynamic linker run-time bindings
    ldconfig

# Set the library path to include both /var/task/lib and standard library paths
ENV LD_LIBRARY_PATH=/var/task/lib:/usr/lib64:/usr/local/lib64:./bin:/var/task/bin/lib
# Create necessary symlinks and verify ClamAV functionality
RUN ln -sf /var/task/lib/libfreshclam.so.3.0.2 /var/task/lib/libfreshclam.so.3 && \
    ln -sf /var/task/lib/libclamav.so.12.0.3 /var/task/lib/libclamav.so.9 && \
    ln -sf /var/task/lib/libclammspack.so.0.8.0 /var/task/lib/libclammspack.so.0 && \
    # Also put libraries directly in bin directory for direct access
    cp /var/task/lib/libfreshclam.so.3.0.2 /var/task/bin/ && \
    ln -sf /var/task/bin/libfreshclam.so.3.0.2 /var/task/bin/libfreshclam.so.3 && \
    # Also create symlinks in bin directory for compatibility
    mkdir -p /var/task/bin/lib && \
    cp /var/task/lib/*.so* /var/task/bin/lib/ && \
    # Create symlink for freshclam.conf in the expected location
    ln -sf /var/task/freshclam.conf /var/task/bin/freshclam.conf && \
    # Verify ClamAV binary compatibility
    /var/task/bin/clamscan --version && \
    # Verify freshclam functionality
    mkdir -p /tmp/clamav && \
    chmod +x /var/task/bin/freshclam && \
    LD_LIBRARY_PATH=/var/task/lib:/usr/lib64:/usr/local/lib64:/var/task/bin/lib \
    /var/task/bin/freshclam --config-file=./bin/freshclam.conf --version

# Install dependencies and prepare runtime directories
RUN pip3.11 install --no-cache-dir -r requirements.txt --target /var/task awslambdaric && \
    # Make sure directories needed at runtime are writeable by upgrade user
    mkdir -p /tmp/clamav /tmp/clamav_defs && \
    chown -R upgrade:upgrade /tmp/clamav /tmp/clamav_defs

# Switch to the upgrade user for better security
USER upgrade

ENTRYPOINT [ "python3.11", "-m", "awslambdaric" ]
