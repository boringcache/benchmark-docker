# syntax=docker/dockerfile:1.7
# Licensed to the Apache Software Foundation (ASF) under one
# or more contributor license agreements.  See the NOTICE file
# distributed with this work for additional information
# regarding copyright ownership.  The ASF licenses this file
# to you under the Apache License, Version 2.0 (the
# "License"); you may not use this file except in compliance
# with the License.  You may obtain a copy of the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing,
# software distributed under the License is distributed on an
# "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
# KIND, either express or implied.  See the License for the
# specific language governing permissions and limitations
# under the License.

FROM debian:trixie-slim AS build

ARG MORE_BUILD_ARGS
ARG SCCACHE_VERSION=v0.17.0
ARG SCCACHE_SHA256_AMD64=67c4a96dd237c1f518f6b36083f270f9976d516f1e57fce891755ea782e50006
ARG SCCACHE_SHA256_ARM64=821a86343191aa1cbab74bd42f9e93c9a63bf85e4742945f40d3ae84193c1c77
ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get upgrade -y && apt-get -y --no-install-recommends install git build-essential autoconf cmake libtool python3 libssl-dev clang ca-certificates curl tar && apt-get autoremove && apt-get clean

RUN set -eux; \
    arch="$(dpkg --print-architecture)"; \
    case "$arch" in \
      amd64) sccache_arch="x86_64"; sccache_sha256="$SCCACHE_SHA256_AMD64" ;; \
      arm64) sccache_arch="aarch64"; sccache_sha256="$SCCACHE_SHA256_ARM64" ;; \
      *) echo "unsupported sccache architecture: ${arch}" >&2; exit 1 ;; \
    esac; \
    archive="/tmp/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl.tar.gz"; \
    curl -fsSL "https://github.com/mozilla/sccache/releases/download/${SCCACHE_VERSION}/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl.tar.gz" -o "$archive"; \
    echo "${sccache_sha256}  ${archive}" | sha256sum -c -; \
    tar xzf "$archive" -C /tmp; \
    mv "/tmp/sccache-${SCCACHE_VERSION}-${sccache_arch}-unknown-linux-musl/sccache" /usr/local/bin/sccache; \
    rm -f "$archive"; \
    chmod +x /usr/local/bin/sccache; \
    sccache --version

WORKDIR /kvrocks

COPY . .
RUN --mount=type=secret,id=boringcache-tool-cache-env \
    set -eux; \
    . /run/secrets/boringcache-tool-cache-env; \
    export SCCACHE_ERROR_LOG=/tmp/sccache.log; \
    sccache --start-server; \
    ./x.py build --compiler=clang -DCMAKE_EXE_LINKER_FLAGS="-latomic" -DENABLE_OPENSSL=ON -DPORTABLE=1 -DCMAKE_BUILD_TYPE=Release -j $(nproc) $MORE_BUILD_ARGS; \
    echo BEGIN_BORINGCACHE_SCCACHE_STATS; \
    sccache --show-stats; \
    echo END_BORINGCACHE_SCCACHE_STATS

FROM debian:trixie-slim

RUN apt-get update && apt-get upgrade -y && apt-get -y install openssl ca-certificates redis-tools binutils && apt-get clean

# Create a dedicated non-root user and group
RUN groupadd --gid=999 -r kvrocks && useradd --uid=999 -r -g kvrocks kvrocks

RUN mkdir /var/run/kvrocks /var/lib/kvrocks && \
    chown -R kvrocks:kvrocks /var/run/kvrocks /var/lib/kvrocks

# Switch to the non-root user
USER 999

VOLUME /var/lib/kvrocks

COPY --from=build /kvrocks/build/kvrocks /bin/

HEALTHCHECK --interval=30s --timeout=3s --start-period=30s --retries=3 \
    CMD redis-cli -p 6666 PING | grep -E '(PONG|NOAUTH)' || exit 1

COPY ./LICENSE ./NOTICE ./licenses /kvrocks/
COPY ./kvrocks.conf /var/lib/kvrocks/

ENV MALLOC_CONF="prof:true,prof_active:false,background_thread:true"

EXPOSE 6666:6666

ENTRYPOINT ["kvrocks", "-c", "/var/lib/kvrocks/kvrocks.conf", "--dir", "/var/lib/kvrocks", "--pidfile", "/var/run/kvrocks/kvrocks.pid", "--bind", "0.0.0.0"]
