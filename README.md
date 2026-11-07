# Slyber SFU Server

High performance WebRTC Selective Forwarding Unit (SFU) with an embedded zero hop TURN relay, single port UDP/TCP multiplexer, WHIP/WHEP broadcasting, Media over QUIC (MoQ) bridge, and a real-time AI voice media pipe.

## Key features

* **Zero allocation media hot path**: Routes RTP/SRTP packets in ~89 ns/op with `0 B/op` and `0 allocs/op` using pre-allocated packet pools and copy-on-write subscriber snapshots.
* **Single port multiplexing (port 443)**: Consolidates STUN, DTLS 1.2, SRTP, SRTCP, RFC 4571 ICE-TCP, TURN ChannelData, and QUIC packets on a single port to traverse strict NATs and corporate firewalls.
* **Embedded zero hop TURN**: Eliminates external relay hops by unwrapping TURN ChannelData directly inside the SFU ingress pipeline.
* **Simulcast, SVC, and 1v1 roulette swap**: Supports 3 spatial layers with automatic layer clamping, per-layer PLI coalescing, NACK ring buffers, Last-N active speaker pausing, and instant track swapping without renegotiating SDP.
* **End to end security**: Enforces STUN `MESSAGE-INTEGRITY` address latching, BUNDLE-aware SRTP rollover counters, SFrame E2EE payload validation with an RFC 6479 64-packet anti-replay window, and per-track token-bucket rate limiting.
* **Built in gateways**: Native endpoints for WebSocket/HTTP signaling, WHIP/WHEP ingest and playback, MoQ (`moqt-draft-22`) CDN relay, inter-node cascade pipes, and a raw Opus AI voice gateway with VAD barge in detection.

---

## Quick start

### 1. Linux one-line installation (systemd)

Install the precompiled binary (`amd64` / `arm64`), apply kernel UDP buffer tuning, generate isolated cryptographic secrets, and register the `slyber_sfu` systemd service:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/install.sh | sudo bash
```

Check service health and run self diagnostics:

```bash
sudo systemctl status slyber_sfu
sudo slyber_sfu doctor
```

### 2. Run with Docker

```bash
docker run -d \
  --name slyber-sfu \
  --network host \
  --restart unless-stopped \
  -e PUBLIC_IP="203.0.113.10" \
  -e REALM="slyber.com" \
  -e AUTH_MODE="secret" \
  -e TURN_SECRET="your-turn-hmac-secret" \
  -e JWT_SECRET="your-room-jwt-secret" \
  -e NODE_SECRET="your-node-admin-secret" \
  ghcr.io/slyber-app/slyber-sfu-server:latest
```

### 3. Run with Docker Compose

```bash
curl -fsSLO https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/docker-compose.yml
PUBLIC_IP="203.0.113.10" docker compose up -d
```

---

## Authentication modes

Slyber SFU Server supports three client authentication backends configured via `AUTH_MODE` and a dedicated `NODE_SECRET` for administrative and inter node endpoints:

1. **`secret` (HMAC-SHA1)**: Validates time limited credentials formatted as `expires_at:participant_id:base64_hmac` signed with `TURN_SECRET`.
2. **`jwt` (HS256)**: Verifies JSON Web Tokens signed with `JWT_SECRET` containing room profile, E2EE requirements, and per-track bitrate/layer capabilities.
3. **`redis`**: Validates active session tokens against Redis keys (`slyber:session:<token>`) using persistent pooled connections with automatic socket retry.

Generate a development token and TURN credentials using your `NODE_SECRET`:

```bash
curl -s -H "X-Slyber-Node-Secret: <your-node-secret>" \
  "http://127.0.0.1:8090/auth/token?room=main-hall&user=alice"
```

---

## Configuration reference

All parameters can be passed via environment variables (`.env`) or CLI flags:

| Environment variable | CLI flag | Default | Description |
| :--- | :--- | :--- | :--- |
| `SFU_NODE_ID` | `-node-id` | `slyber-sfu-01` | Unique node identifier |
| `PUBLIC_IP` | `-public-ip` | `127.0.0.1` | Public IPv4 advertised in ICE candidates |
| `REALM` | `-realm` | `slyber.com` | Authentication realm |
| `DEFAULT_ROOM_PROFILE` | - | `conference` | Room profile (`conference`, `roulette_1v1`, `broadcast`, `gaming`, `ai_voice`) |
| `SFU_UDP_PORT` | `-udp-port` | `443` | Single port UDP multiplexer port |
| `SFU_TCP_PORT` | `-tcp-port` | `443` | Single port TCP/ICE-TCP multiplexer port |
| `SFU_HTTP_PORT` | `-http-port` | `8090` | HTTP signaling, gateways, and telemetry port |
| `SO_REUSEPORT_WORKERS` | `-workers` | `4` | Number of UDP socket reader workers |
| `ENABLE_ICE_TCP` | `-enable-ice-tcp` | `true` | Enable RFC 4571 ICE-TCP transport |
| `ENABLE_QUIC` | `-enable-quic` | `true` | Enable QUIC / WebTransport media ingress |
| `TURN_MODE` | `-turn-mode` | `both` | TURN mode (`embedded`, `external`, `both`, `off`) |
| `AUTH_MODE` | `-auth-mode` | `secret` | Session auth mode (`secret`, `jwt`, `redis`) |
| `TURN_SECRET` | `-turn-secret` | auto generated | Shared HMAC secret for TURN and session tokens |
| `JWT_SECRET` | `-jwt-secret` | auto generated | HS256 secret for room JWT verification |
| `NODE_SECRET` | `-node-secret` | auto generated | Admin secret for `/auth/token`, `/cascade`, `/ai`, `/metrics` |
| `REQUIRE_SRTP` | `-require-srtp` | `false` | Reject packets without an active DTLS-SRTP context |
| `REQUIRE_E2EE` | `-require-e2ee` | `false` | Enforce SFrame / MLS End-to-End Encryption |
| `MAX_KBPS_PER_TRACK` | `-max-kbps-track` | `3500` | Maximum incoming bitrate per track (kbps) |
| `MAX_KBPS_PER_SESSION` | `-max-kbps-session` | `10000` | Maximum incoming bitrate per session (kbps) |
| `REDIS_ADDR` | `-redis-addr` | `127.0.0.1:6379` | Redis server address (`host:port`) |
| `LAST_N_VIDEO_LIMIT` | `-last-n` | `16` | Maximum active video tracks per room |

---

## HTTP endpoints and gateways

* **`GET /ws`** - WebSocket signaling gateway (`join`, `offer`, `publish_track`, `subscribe_track`, `set_layer`, `roulette_swap`, `e2ee_key_ratchet`).
* **`POST /signaling`** - Stateless HTTP JSON signaling endpoint.
* **`GET /auth/token`** - Generates development JWTs and TURN credentials (requires `X-Slyber-Node-Secret`).
* **`POST /whip/{room_id}/{track_id}`** - WHIP ingest endpoint for OBS and hardware encoders.
* **`POST /whep/{room_id}/{track_id}`** - WHEP sub second playback endpoint.
* **`GET /moq/{room_id}/{track_id}`** - Media over QUIC (`moqt-draft-22`) group and object relay snapshot.
* **`POST /ai/?room={room_id}`** - Injects raw Opus frames from AI voice agents into a room (requires `X-Slyber-Node-Secret`).
* **`POST /cascade/`** - Subscribes remote SFU nodes to local tracks with built-in SSRF protection (requires `X-Slyber-Node-Secret`).
* **`GET /inspector/stats`** - Real time JSON telemetry for Slyber Inspector.
* **`GET /metrics`** - Prometheus metrics exporter (requires `X-Slyber-Node-Secret`).
* **`GET /healthz`** - Liveness probe returning `200 OK`.

---

## Uninstallation

To stop the service and remove the binary while preserving `/opt/slyber_sfu/.env`:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/uninstall.sh | sudo bash
```

To completely remove all configuration files and the system user:

```bash
curl -fsSL https://raw.githubusercontent.com/slyber-app/slyber-sfu-server/main/uninstall.sh | sudo PURGE_DATA=true bash
```