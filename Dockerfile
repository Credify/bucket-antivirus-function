FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20251124100839-6eca34dc as build-image

USER root

# Set up working directories
WORKDIR /app
COPY . /app

RUN pip3.11 install --no-cache-dir -r requirements-dev.txt
# hadolint ignore=DL3059
RUN python3.11 -m unittest

FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/container-base-2023:20251122101032-a82092dd as clamav-image

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
    # Copy binaries
    cp usr/local/bin/clamscan /clamav/bin/ && \
    cp usr/local/bin/freshclam /clamav/bin/ && \
    # Copy all library files
    cp -r usr/local/lib64/* /clamav/lib/ && \
    # Make binaries executable
    chmod +x /clamav/bin/clamscan /clamav/bin/freshclam && \
    # Clean up
    rm -rf /tmp/clamav.rpm

# Download and extract system dependencies in a single layer
WORKDIR /var/cache/dnf
RUN dnf download json-c pcre2 pcre libprelude gnutls libtasn1 nettle openssl-libs && \
    # Extract all RPMs
    for rpm in *.rpm; do \
        echo "Extracting $rpm"; \
        rpm2cpio $rpm | cpio -idmv || true; \
    done && \
    # Copy needed libraries
    cp -r /var/cache/dnf/usr/lib64/* /clamav/lib/ || true

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


FROM 118455887602.dkr.ecr.us-west-2.amazonaws.com/releases/images/python311-base-legacy:20251124100839-6eca34dc

USER root

RUN dnf install -y libtool-ltdl binutils

WORKDIR /var/task

# Copy all dependencies from previous layers
COPY --chown=upgrade:upgrade --from=build-image /app/*.py /var/task
COPY --chown=upgrade:upgrade --from=build-image /app/requirements.txt /var/task/requirements.txt
COPY --chown=upgrade:upgrade --from=build-image /app/custom_clamav_rules /var/task/bin/custom_clamav_rules
COPY --from=clamav-image /clamav /var/task

# Set up library environment for ClamAV
RUN mkdir -p /var/task/lib && \
    # Fix permissions for Lambda execution
    chown -R upgrade:upgrade /var/task && \
    chmod -R 755 /var/task/bin && \
    chmod 644 /var/task/*.py && \
    chmod 755 /var/task/bin/freshclam /var/task/bin/clamscan && \
    # Copy freshclam.conf to bin directory where it's expected
    cp /var/task/freshclam.conf /var/task/bin/

# Set up the proper library environment for ClamAV
ENV LD_LIBRARY_PATH=/var/task/lib:/var/task/bin:/usr/lib64:/usr/local/lib64
# Create a clean library setup with minimal required libraries and symlinks
RUN echo "Setting up ClamAV libraries" && \
    # Copy required libraries to bin directory where freshclam will find them
    cp /var/task/lib/libfreshclam.so.3.0.2 /var/task/bin/ && \
    cp /var/task/lib/libclamav.so.12.0.3 /var/task/bin/ && \
    cp /var/task/lib/libclammspack.so.0.8.0 /var/task/bin/ && \
    # Create necessary symlinks
    ln -sf /var/task/lib/libfreshclam.so.3.0.2 /var/task/lib/libfreshclam.so.3 && \
    ln -sf /var/task/bin/libfreshclam.so.3.0.2 /var/task/bin/libfreshclam.so.3 && \
    ln -sf /var/task/lib/libclamav.so.12.0.3 /var/task/lib/libclamav.so.12 && \
    ln -sf /var/task/bin/libclamav.so.12.0.3 /var/task/bin/libclamav.so.12 && \
    ln -sf /var/task/lib/libclammspack.so.0.8.0 /var/task/lib/libclammspack.so.0 && \
    ln -sf /var/task/bin/libclammspack.so.0.8.0 /var/task/bin/libclammspack.so.0 && \
    # Verify ClamAV is working
    echo "Verifying ClamAV binary compatibility" && \
    /var/task/bin/clamscan --version

# Test freshclam version
RUN echo "Testing freshclam execution with correct library path" && \
    mkdir -p /tmp/clamav && \
    echo "Verifying freshclam version" && \
    /var/task/bin/freshclam --config-file=/var/task/bin/freshclam.conf --version

# Install Python dependencies
RUN pip3.11 install --no-cache-dir -r requirements.txt --target /var/task awslambdaric

# Set up runtime directories
RUN mkdir -p /tmp/clamav && chown -R upgrade:upgrade /tmp/clamav && \
    mkdir -p /tmp/clamav_defs && chown -R upgrade:upgrade /tmp/clamav_defs

# Switch to the upgrade user for better security
USER upgrade

ENTRYPOINT [ "python3.11", "-m", "awslambdaric" ]
