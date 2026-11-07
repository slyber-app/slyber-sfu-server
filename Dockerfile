FROM alpine:3.20

ARG TARGETARCH
ARG VERSION=latest
ARG VCS_REF=unknown

LABEL org.opencontainers.image.title="Slyber SFU Server" \
      org.opencontainers.image.description="High-Performance Single-Port WebRTC SFU, Embedded TURN, WHIP/WHEP, QUIC/MoQ & AI Media Server" \
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

ENV SFU_NODE_ID="slyber-sfu-01" \
    REALM="slyber.com" \
    SFU_UDP_PORT="443" \
    SFU_TCP_PORT="443" \
    SFU_HTTP_PORT="8090" \
    SO_REUSEPORT_WORKERS="4" \
    ENABLE_ICE_TCP="true" \
    ENABLE_QUIC="true" \
    TURN_MODE="both" \
    AUTH_MODE="secret"

EXPOSE 443/udp 443/tcp 8090/tcp

VOLUME ["/data"]

USER slyber_sfu:slyber_sfu

ENTRYPOINT ["/usr/local/bin/slyber_sfu"]
CMD ["server"]