# Slyber SFU Server

[![Docs](https://img.shields.io/badge/docs-official-blue.svg)](https://slyber.com/docs/slyber-sfu-server/overview)
[![Website](https://img.shields.io/badge/website-slyber.com-success.svg)](https://slyber.com/slyber-sfu-server)

High performance WebRTC Selective Forwarding Unit (SFU) built with Go and Pion WebRTC v4, featuring a single port ICE-Lite UDP/TCP multiplexer, Simulcast & VP9 SVC routing, WHIP/WHEP broadcasting, SFrame End to End Encryption (E2EE), inter-node HMAC cascading, and a full duplex AI voice WebSocket pipe.

## Key features

- **Zero allocation media hot path**: Routes RTP packets using pre allocated `sync.Pool` packet buffers (`SlyberPacket`), atomic reference counting, in place RFC 3550/8285 header parsing, and copy on write subscriber snapshots.
- **Pion WebRTC v4 single port multiplexing (port 4443)**: Consolidates ICE-Lite UDP (`ICEUDPMux`), RFC 4571 ICE-TCP (`ICETCPMux`), DTLS-SRTP encryption, TWCC sender feedback, and NACK generation on a single media port (`4443` by default).
- **Simulcast, VP9 SVC & 1v1 roulette fast swap**: Supports up to 3 spatial and 3 temporal layers with automatic spatial layer clamping (`ClampSpatialLayer`), per layer NACK ring buffers, independent per layer PLI coalescers (`500ms`), Last-N active speaker pausing (RFC 6464), and sub millisecond track swapping (`FastSwapRouletteTrack`) with gapless `SeqTimestampRewriter` translation.
- **SFrame E2EE & multi-backend authentication**: Enforces RFC 9605 SFrame payload validation with a 512-packet RTP sequence anti-replay bitmap, per-KeyID counter windows, seamless MLS key rotation (up to 16 active keys per track), RFC 9626 Frame Marking parsing, and lock-free token-bucket rate limiting (`TrafficPolice`).
- **Full duplex AI voice gateway (`/ai/ws`)**: Streams raw Opus audio between room participants and AI agents (such as Gemini Live or OpenAI Realtime) over WebSocket in single or multiplexed (`mode=mux`) multi-bot mode with a built-in 20ms pacer and automatic queue flushing on RFC 6464 VAD barge-in.
- **Built-in WHIP/WHEP, MoQ & Cascade gateways**: Native HTTP endpoints for 1-RTT WHIP ingest and WHEP playback with ETag owner protection, Media over QUIC (`moqt-draft-22`) group packaging, and HMAC-SHA256 authenticated inter-node UDP cascading with SSRF protection.

---

## Quick start

### 1. Linux one line installation

Install the precompiled static binary (`amd64` / `arm64`), apply kernel UDP buffer tuning (`8 MB`), generate isolated cryptographic secrets in `/opt/slyber_sfu/.env`, and start the `slyber_sfu` systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/install.sh | sudo bash
```

Check service health and run self-diagnostics:

```bash
sudo systemctl status slyber_sfu
sudo slyber_sfu doctor
```

### 2. Run with Docker

Pull the official multi arch image (`linux/amd64`, `linux/arm64`), auto-detect your public IPv4 address, generate production secrets, and run self diagnostics:

```bash
docker pull ghcr.io/slyber-app/slyber-sfu-server:latest
docker rm -f slyber-sfu-server 2>/dev/null || true

PUBLIC_IP=$(curl -fsSL4 --max-time 2 api.ipify.org 2>/dev/null || echo 127.0.0.1)
JWT_SECRET=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')
NODE_SECRET=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d ' \n')

docker run -d \
  --name slyber-sfu-server \
  --restart unless-stopped \
  --network host \
  -e SFU_ENV="production" \
  -e PUBLIC_IP="${PUBLIC_IP}" \
  -e SFU_UDP_PORT="4443" \
  -e SFU_TCP_PORT="4443" \
  -e SFU_HTTP_PORT="8090" \
  -e AUTH_MODE="jwt" \
  -e JWT_SECRET="${JWT_SECRET}" \
  -e NODE_SECRET="${NODE_SECRET}" \
  ghcr.io/slyber-app/slyber-sfu-server:latest && \
  sleep 1 && \
  docker exec slyber-sfu-server slyber_sfu doctor && \
  echo "Public IP  : ${PUBLIC_IP}" && \
  echo "JWT Secret : ${JWT_SECRET}" && \
  echo "Node Secret: ${NODE_SECRET}" && \
  echo "Test Token : $(curl -fsS -H "X-Slyber-Node-Secret: ${NODE_SECRET}" "http://127.0.0.1:8090/auth/token?room=test-room&user=user-1")"
```

### 3. Run with Docker Compose

```bash
curl -fsSLO https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/docker-compose.yml
PUBLIC_IP="203.0.113.10" \
JWT_SECRET="your-24-char-production-jwt-secret" \
NODE_SECRET="your-24-char-production-node-secret" \
docker compose up -d
```

---

## Authentication modes

[Slyber SFU Server](https://slyber.com/slyber-sfu-server) supports three client authentication backends configured via `AUTH_MODE`, plus a dedicated `NODE_SECRET` for administrative and inter-node endpoints:

1. **`jwt` (HS256, default)**: Verifies JSON Web Tokens signed with `JWT_SECRET` containing `sub`, `room_id`, non-zero `exp`, room `profile`, E2EE requirements, and per-track capabilities (`can_publish`, `can_subscribe`, `max_spatial_layer`, `max_bitrate_kbps`).
2. **`redis`**: Validates active session tokens against Redis keys (`slyber:session:<token>`) using a persistent connection pool with RESP injection protection and automatic retry.
3. **`secret` (HMAC-SHA1)**: Validates time-limited credentials formatted as `expires_at:participant_id:base64_hmac` signed with `TURN_SECRET`.

Generate a ready-to-use JWT, TURN HMAC token, and external ICE server list using your `NODE_SECRET`:

```bash
curl -s -H "X-Slyber-Node-Secret: <your-node-secret>" \
  "http://127.0.0.1:8090/auth/token?room=main-hall&user=alice"
```

---

## Configuration reference

All parameters can be configured via environment variables (`.env`) or CLI flags:

| Environment variable | CLI flag | Default | Description |
| :--- | :--- | :--- | :--- |
| `SFU_ENV` | `-env` | `development` | Runtime environment (`development` or `production`) |
| `SFU_NODE_ID` | `-node-id` | `slyber-sfu-01` | Unique SFU node identifier |
| `PUBLIC_IP` | `-public-ip` | `auto` | Public IPv4 address advertised in ICE candidates |
| `REALM` | `-realm` | `slyber.com` | Authentication realm |
| `DEFAULT_ROOM_PROFILE` | - | `conference` | Default room profile (`conference`, `roulette_1v1`, `broadcast`, `gaming`, `ai_voice`) |
| `SFU_UDP_PORT` | `-udp-port` | `4443` | Single-port Pion ICE-UDP mux port |
| `SFU_TCP_PORT` | `-tcp-port` | `4443` | Single-port Pion ICE-TCP (RFC 4571) mux port |
| `SFU_HTTP_PORT` | `-http-port` | `8090` | HTTP signaling, WHIP/WHEP, AI pipe, and telemetry port |
| `ENABLE_ICE_TCP` | `-enable-ice-tcp` | `true` | Enable RFC 4571 ICE-TCP multiplexer |
| `ALLOW_PORT_FALLBACK` | `-allow-port-fallback` | `false` | Automatically select the next free port if busy |
| `SOCKET_BUFFER_BYTES` | `-socket-buffer` | `8388608` | OS UDP socket read/write buffer size in bytes (`8 MB`) |
| `EXTERNAL_TURN_URLS` | `-external-turn-urls` | - | Comma-separated external TURN server URLs |
| `AUTH_MODE` | `-auth-mode` | `jwt` | Session authentication mode (`jwt`, `redis`, `secret`) |
| `JWT_SECRET` | `-jwt-secret` | auto-generated (dev) | HMAC-SHA256 secret for room JWT tokens (min 24 chars in prod) |
| `TURN_SECRET` | `-turn-secret` | auto-generated (dev) | Shared HMAC-SHA1 secret for external TURN and `secret` auth |
| `NODE_SECRET` | `-node-secret` | auto-generated (dev) | Dedicated admin secret for `/auth/token`, `/ai`, `/cascade`, `/metrics` |
| `ALLOWED_ORIGINS` | `-allowed-origins` | `https://slyber.com` | Comma-separated allowed WebSocket and CORS origins |
| `ALLOW_INTERNAL_CASCADE` | `-allow-internal-cascade` | `false` | Allow loopback/RFC1918 IPs in inter-node cascade pipe |
| `CREDENTIAL_TTL_SEC` | `-credential-ttl` | `3600` | TTL for generated credentials in seconds |
| `REQUIRE_E2EE` | `-require-e2ee` | `false` | Enforce RFC 9605 SFrame / MLS End-to-End Encryption |
| `REDIS_ADDR` | `-redis-addr` | `127.0.0.1:6379` | Redis server address (`host:port`) |
| `REDIS_USERNAME` | `-redis-user` | - | Optional Redis ACL username |
| `REDIS_PASSWORD` | `-redis-pass` | - | Optional Redis password |
| `REDIS_DB` | `-redis-db` | `0` | Redis database index |
| `MAX_KBPS_PER_TRACK` | `-max-kbps-track` | `25000` (`3500` in Docker) | Maximum incoming bitrate per track (kbps) |
| `MAX_KBPS_PER_SESSION` | `-max-kbps-session` | `100000` (`10000` in Docker) | Maximum total incoming bitrate per session (kbps) |
| `ENABLE_SIMULCAST` | `-enable-simulcast` | `true` | Enable Simulcast spatial layer routing |
| `ENABLE_SVC` | `-enable-svc` | `true` | Enable VP9 SVC spatial/temporal filtering |
| `VIDEO_CODECS` | - | `VP9,AV1,H264,VP8` | Comma-separated list of enabled video codecs |
| `NACK_BUFFER_SIZE` | `-nack-buffer` | `512` | Per-layer ring buffer size for NACK retransmissions |
| `LAST_N_VIDEO_LIMIT` | `-last-n` | `16` | Maximum active video streams per room |
| `DYNACAST_ENABLED` | `-dynacast` | `true` | Automatically adapt subscriber layers based on BWE feedback |
| `ENABLE_WHIP_WHEP` | `-enable-whip-whep` | `true` | Enable `/whip/` and `/whep/` endpoints |
| `ENABLE_MOQ_RELAY` | `-enable-moq` | `false` | Enable `/moq/` packaging endpoint |
| `ENABLE_AI_GATEWAY` | `-enable-ai` | `true` | Enable `/ai` and `/ai/ws` voice media pipe |
| `ENABLE_CASCADE_PIPE` | `-enable-cascade` | `true` | Enable `/cascade/` inter-node UDP cascading |
| `ENABLE_INSPECTOR` | `-enable-inspector` | `true` | Expose `/inspector/stats` and `/metrics` endpoints |

---

## HTTP endpoints and gateways

- **`GET /ws`**: WebSocket signaling gateway (`join`, `offer`, `answer`, `trickle_ice`, `publish_track`, `subscribe_track`, `set_layer`, `roulette_swap`, `e2ee_key_ratchet`, `leave`).
- **`POST /signaling`**: Stateless HTTP JSON signaling endpoint.
- **`GET /auth/token`**: Generates development JWTs, TURN HMAC tokens, and ICE server configs (requires `X-Slyber-Node-Secret`).
- **`POST | PATCH | DELETE /whip/{room_id}/{track_id}`**: 1-RTT WHIP broadcast ingest endpoint with Trickle ICE and ETag owner protection.
- **`POST | PATCH | DELETE /whep/{room_id}/{track_id}`**: 1-RTT WHEP viewer playback endpoint.
- **`GET /ai/ws?room={room_id}&mode=mux`**: Full-duplex AI voice WebSocket supporting single and multiplexed multi-bot streams, 20ms Opus pacing, and RFC 6464 VAD barge-in queue flushing (requires `X-Slyber-Node-Secret`).
- **`POST /ai?room={room_id}`**: Injects single raw Opus frames from AI voice agents into a room (requires `X-Slyber-Node-Secret`).
- **`POST | GET | DELETE /cascade/`**: Connects SFU nodes via HMAC-SHA256 signed UDP pipes with built-in SSRF protection (requires `X-Slyber-Node-Secret`).
- **`GET /moq/{room_id}/{track_id}`**: Media over QUIC (`moqt-draft-22`) group and object relay snapshot (requires Bearer token with subscribe capability).
- **`GET /inspector/stats`**: Real-time JSON telemetry for Slyber Inspector (requires `X-Slyber-Node-Secret`).
- **`GET /metrics`**: Lock-free Prometheus metrics exporter (requires `X-Slyber-Node-Secret`).
- **`GET /healthz`**: Liveness probe returning `200 OK`.

---

## Uninstallation

To stop the service and remove the binary while preserving `/opt/slyber_sfu/.env`:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/uninstall.sh | sudo bash
```

To completely remove all configuration files and the `slyber_sfu` system user:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/uninstall.sh | sudo env PURGE_DATA=true bash
```