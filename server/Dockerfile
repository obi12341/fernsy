# Fernsy Server image (headless-recorder design 7): a static Swift binary (Swift Static Linux SDK,
# musl) in an otherwise empty image with CA certificates and time zones. Built from the
# repository root, for linux/amd64 and linux/arm64; the build stage runs natively and
# cross-compiles, so no emulation is needed:
#
#   docker buildx build -f server/Dockerfile --platform linux/amd64,linux/arm64 .
FROM --platform=$BUILDPLATFORM swift:6.4.2-noble AS build
ARG TARGETARCH
# `debug` for tests against the dev services: only debug builds read IPTV_CLOUD/IPTV_CLOUDTOKEN.
ARG CONFIGURATION=release
# Checksum from swift.org (api/v1/install/releases.json, 6.4.2, Static SDK 0.1.0).
RUN swift sdk install \
    https://download.swift.org/swift-6.4.2-release/static-sdk/swift-6.4.2-RELEASE/swift-6.4.2-RELEASE_static-linux-0.1.0.artifactbundle.tar.gz \
    --checksum 3786b179936d9cc9e266dd506bd1654176358d7b25288e243359f4d17cc4dc5a
WORKDIR /src
COPY Packages/FernsyCore Packages/FernsyCore
COPY server server
RUN case "$TARGETARCH" in amd64) ARCH=x86_64 ;; arm64) ARCH=aarch64 ;; *) echo "unsupported $TARGETARCH" >&2; exit 1 ;; esac \
    && cd server \
    && swift build -c "$CONFIGURATION" --swift-sdk "$ARCH-swift-linux-musl" -Xswiftc -gnone -Xlinker --strip-all \
    && cp "$(swift build -c "$CONFIGURATION" --swift-sdk "$ARCH-swift-linux-musl" -Xswiftc -gnone -Xlinker --strip-all --show-bin-path)/FernsyServer" /fernsy-server

FROM scratch
COPY --from=build /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
COPY --from=build /usr/share/zoneinfo /usr/share/zoneinfo
COPY --from=build /fernsy-server /fernsy-server
ENV FERNSY_DATA=/data FERNSY_PORT=8080
VOLUME /data
EXPOSE 8080
ENTRYPOINT ["/fernsy-server"]
