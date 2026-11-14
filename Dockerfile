FROM alpine:3.20

ARG TARGETARCH
ARG VERSION=latest
ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="Slyber SFU Server" \
      org.opencontainers.image.description="High-Performance Pion WebRTC v4 SFU, Single-Port ICE-Lite UDP/TCP Mux, Simulcast/SVC, WHIP/WHEP, SFrame E2EE & AI Voice Pipe" \
      org.opencontainers.image.source="https://github.com/slyber-app/slyber-sfu-server" \
      org.opencontainers.image.version="${VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}"

RUN apk add --no-cache ca-certificates tzdata libcap && \
    addgroup -S -g 10001 slyber_sfu && \
    adduser -S -u 10001 -G slyber_sfu -h /data -s /sbin/nologin slyber_sfu && \
    mkdir -p /data/certs && \
    chown -R slyber_sfu:slyber_sfu /data

COPY bin/slyber_sfu-linux-${TARGETARCH} /usr/local/bin/slyber_sfu
COPY bin/SHA256SUMS /tmp/SHA256SUMS

RUN grep " slyber_sfu-linux-${TARGETARCH}\$" /tmp/SHA256SUMS | awk '{print $1 "  /usr/local/bin/slyber_sfu"}' | sha256sum -c - && \
    rm -f /tmp/SHA256SUMS && \
    chmod 0755 /usr/local/bin/slyber_sfu && \
    setcap 'cap_net_bind_service=+ep' /usr/local/bin/slyber_sfu

WORKDIR /data

ENV SFU_ENV="production" \
    SFU_NODE_ID="slyber-sfu-01" \
    REALM="slyber.com" \
    DEFAULT_ROOM_PROFILE="conference" \
    SFU_UDP_PORT="4443" \
    SFU_TCP_PORT="4443" \
    SFU_HTTP_PORT="8090" \
    ENABLE_ICE_TCP="true" \
    ALLOW_PORT_FALLBACK="false" \
    SOCKET_BUFFER_BYTES="8388608" \
    AUTH_MODE="jwt" \
    CREDENTIAL_TTL_SEC="3600" \
    REQUIRE_E2EE="false" \
    ENABLE_SIMULCAST="true" \
    ENABLE_SVC="true" \
    VIDEO_CODECS="VP9,AV1,H264,VP8" \
    NACK_BUFFER_SIZE="512" \
    LAST_N_VIDEO_LIMIT="16" \
    DYNACAST_ENABLED="true" \
    ENABLE_WHIP_WHEP="true" \
    ENABLE_MOQ_RELAY="false" \
    ENABLE_AI_GATEWAY="true" \
    ENABLE_CASCADE_PIPE="true" \
    ENABLE_INSPECTOR="true"

EXPOSE 4443/udp 4443/tcp 8090/tcp

VOLUME ["/data"]

USER slyber_sfu:slyber_sfu

ENTRYPOINT ["/usr/local/bin/slyber_sfu"]
CMD ["server"]