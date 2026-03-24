# Vector FinOps — Docker Compose Deployment Guide

This guide covers deploying Vector FinOps (OptScale) on a single machine using Docker Compose.
No Kubernetes, no Helm, no cluster overhead. Estimated steady-state RAM: **~5–6 GB**.

---

## Prerequisites

### Hardware

| Resource | Minimum | Recommended |
|---|---|---|
| CPU | 4 cores | 8 cores |
| RAM | 8 GB | 12 GB |
| Disk | 40 GB | 100 GB SSD |

### Software

| Software | Version | Notes |
|---|---|---|
| Docker Engine | 24+ | [Install guide](https://docs.docker.com/engine/install/) |
| Docker Compose | v2.20+ (plugin) | Included with Docker Desktop; `docker compose version` to verify |
| `git` | any | |
| Internet access | — | Required to pull images from Docker Hub on first run |

> **nerdctl users:** the commands are identical — replace `docker` with `nerdctl` everywhere.

### Ports

The following ports must be free on the host:

| Port | Service |
|---|---|
| **80** | nginx (main HTTP entry point) |

All other inter-service traffic stays inside the `optscale` Docker network.

---

## Keycloak (SSO) — Pre-requisite

Vector FinOps uses Keycloak for authentication. You need a running Keycloak instance before deploying.

Required Keycloak settings (already configured in `docker-compose.yml`):

| Setting | Value |
|---|---|
| Server URL | `https://keycloak.telemetrics.tech` |
| Realm | `VECTOR` |
| Client ID | `Vector-FinOps` |
| Client Secret | `jbW4OAryh2BkYR0dpxO5LdakfU21p626` |

If your Keycloak details differ, edit these values in `docker-compose.yml` before deploying:

```yaml
# auth service
KEYCLOAK_SERVER_URL: https://your-keycloak-host
KEYCLOAK_REALM: YOUR_REALM
KEYCLOAK_OAUTH_CLIENT_ID: your-client-id
KEYCLOAK_OAUTH_CLIENT_SECRET: your-client-secret

# ngui service
VITE_KEYCLOAK_URL: https://your-keycloak-host
VITE_KEYCLOAK_REALM: YOUR_REALM
VITE_KEYCLOAK_CLIENT_ID: your-client-id
```

---

## Step 1 — Clone the repository

```bash
git clone https://github.com/your-org/optscale.git
cd optscale/optscale-deploy
```

---

## Step 2 — Pull Docker images

All OptScale service images are published to Docker Hub under the `hystax` namespace.
The helper script pulls them and re-tags each as `:local` (the tag used in `docker-compose.yml`).

```bash
# From the optscale-deploy/ directory:
chmod +x pull-images.sh
./pull-images.sh
```

This pulls ~55 images (~8–10 GB total download). It is idempotent — safe to re-run.

**Custom image tag** (if a newer release is available):
```bash
./pull-images.sh 2026012001-public   # default
./pull-images.sh 2026030101-public   # newer release example
```

### Vector branding in the UI

The `ngui:local` image pulled above uses upstream OptScale branding.
The Vector-branded `ngui:local` (custom logo + "Vector" page title) is built from source:

```bash
# From the repo root:
docker build -t ngui:local ngui/
```

> If you already have `ngui:local` from a previous build on the source machine, you can export/import it:
> ```bash
> # On source machine:
> docker save ngui:local | gzip > ngui-local.tar.gz
> # On target machine:
> docker load < ngui-local.tar.gz
> ```

---

## Step 3 — Review configuration

The main configuration files are:

| File | Purpose |
|---|---|
| `docker-compose.yml` | All services, resource limits, environment |
| `docker/etcd-config` | Service registry (hosts/ports written to etcd at startup) |
| `docker/nginx.conf` | URL prefix routing (same as K8s Ingress) |
| `docker/rabbit-definitions.json` | RabbitMQ user + policies |
| `docker/clickhouse/config.xml` | ClickHouse memory tuning (512 MB cache) |
| `docker/ofelia.ini` | Cron job schedule |

### Passwords / secrets

Default credentials used across the stack (change these for production):

| Service | Setting | Default value |
|---|---|---|
| MariaDB | root password | `my-password-01` |
| MongoDB | root password | `SecurePassword-01-02` |
| RabbitMQ | optscale user password | `secure-password-here` |
| ClickHouse | default user password | `secure-password-1-clk` |
| MinIO | access key / secret | `optscale-minio` / `secret_password` |

To change a password, update it in **both** `docker-compose.yml` (environment vars) and `docker/etcd-config` (service registry config) consistently.

### Email (optional)

To enable outbound email for invites and alerts, fill in the `smtp` section in `docker/etcd-config`:

```yaml
smtp:
  server: smtp.example.com
  email: noreply@example.com
  login: noreply@example.com
  port: 587
  password: your-smtp-password
  protocol: starttls
```

---

## Step 4 — Deploy

```bash
# From the optscale-deploy/ directory:
docker compose up -d
```

The startup sequence is:

1. **Infrastructure** starts first: etcd, MariaDB, MongoDB, Redis, RabbitMQ, ClickHouse, InfluxDB, MinIO
2. **Configurator** runs once: writes all config into etcd and creates databases, then exits with code 0
3. **All application services** start after configurator completes
4. **Nginx** starts last and begins accepting traffic

### Watch startup progress

```bash
# Follow configurator (must exit 0 before anything else works):
docker compose logs -f configurator

# Watch all services come up:
docker compose ps

# Follow logs for a specific service:
docker compose logs -f auth
docker compose logs -f restapi
```

### Expected startup time

| Phase | Duration |
|---|---|
| Infrastructure healthy | 1–3 minutes |
| Configurator completes | 30–60 seconds |
| All services running | 3–5 minutes total |

---

## Step 5 — Verify

```bash
# All services should show "running" (configurator will show "exited 0"):
docker compose ps

# Quick health checks:
curl -sf http://localhost/auth/v2/info && echo "auth OK"
curl -sf http://localhost/restapi/v4/info && echo "restapi OK"

# Open in browser:
# http://<your-server-ip>/
```

---

## Architecture overview

```
Browser
  │
  ▼
nginx :80  ──────────────────────────────────────────────
  │  /auth          → auth:8905
  │  /restapi       → restapi:8999
  │  /report        → keeper:8973
  │  /herald        → heraldapi:8906
  │  /katara        → kataraapi:8935
  │  /insider       → insider-api:8945
  │  /slacker       → slacker:80
  │  /metroculus    → metroculusapi:8969
  │  /jira_bus      → jira-bus:8977
  │  /storage       → diproxy:8935
  │  /              → ngui:4000

All services ↔ etcd (service discovery)
All services ↔ MariaDB / MongoDB / Redis / RabbitMQ / ClickHouse / InfluxDB / MinIO
Scheduled jobs → ofelia (cron) → transient containers
Metrics → thanos-receive → thanos-query → grafana
```

---

## Memory usage

Approximate steady-state RSS:

| Group | ~RAM |
|---|---|
| Infrastructure (etcd, MariaDB, MongoDB, Redis, RabbitMQ, InfluxDB, MinIO) | ~700 MB |
| ClickHouse (512 MB + 256 MB cache) | ~900 MB |
| Core API services (auth, restapi, keeper, herald, ngui, …) | ~1.5 GB |
| Workers & schedulers | ~1.7 GB |
| Monitoring (Thanos, Grafana) | ~500 MB |
| nginx, ofelia | ~30 MB |
| **Total** | **~5.3 GB** |

---

## Management commands

```bash
# Stop everything (data volumes preserved):
docker compose down

# Stop + wipe all data volumes (full reset):
docker compose down -v

# Restart a single service:
docker compose restart auth

# View resource usage:
docker stats

# Rebuild after code change:
docker build -t ngui:local /path/to/optscale/ngui/
docker compose up -d --no-deps ngui

# Update to a newer image release:
./pull-images.sh <new-tag>
docker compose up -d
```

---

## Troubleshooting

### Configurator fails or loops

```bash
docker compose logs configurator
```

Common causes:
- MariaDB or MongoDB not yet healthy — configurator will retry, wait 2–3 minutes
- Wrong credentials in `docker/etcd-config` — check `authdb.password` / `mongo.url`

### Service crashes immediately after configurator

```bash
docker compose logs <service-name>
```

Usually means etcd doesn't have the config key the service needs. Confirm configurator exited with code 0:

```bash
docker compose ps configurator
# STATUS should show: exited (0)
```

### MongoDB replica set issues

If MongoDB logs show replica set errors on restart, the keyfile may have wrong permissions:

```bash
docker compose exec mongo bash -c "chmod 400 /data/configdb/key.txt"
docker compose restart mongo
```

### Port 80 already in use

```bash
# Find what is using port 80:
ss -tlnp | grep ':80'
# Stop it, then:
docker compose up -d nginx
```

### Out of memory

If the host has exactly 8 GB RAM and the OS + Docker overhead leaves less than 6 GB free:

```bash
# Reduce thanos-receive (biggest single consumer after ClickHouse):
# Edit docker-compose.yml: thanos-receive mem_limit: 512m
# Then:
docker compose up -d --no-deps thanos-receive
```

---

## Upgrading

1. Pull new images: `./pull-images.sh <new-tag>`
2. Apply: `docker compose up -d`

Docker Compose will only restart services whose image changed.

---

## Difference from Kubernetes deployment

| Aspect | Kubernetes | Docker Compose |
|---|---|---|
| Overhead | ~756 MB (control plane) | ~0 MB |
| Ingress | nginx-ingress controller | nginx container |
| CronJobs | 25 K8s CronJob objects | ofelia scheduler container |
| Service discovery | K8s DNS + ClusterIP :80 | Docker network + actual ports |
| Config injection | ConfigMap → etcd | `docker/etcd-config` → etcd |
| Scaling | `kubectl scale` | `docker compose up --scale` |
| HA / rolling updates | built-in | manual |
