# Vector FinOps — Single Container Deployment

Deploy Vector FinOps (FinOps & multi-cloud cost management) as a **single Docker container** running all 47 services via supervisord. No Kubernetes, no Docker Swarm, no external dependencies.

## Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| RAM      | 6 GB    | 8–10 GB     |
| CPU      | 2 cores | 4 cores     |
| Disk     | 20 GB   | 40 GB       |
| OS       | Any Linux with Docker | Ubuntu 22.04+ |

Docker Engine 24+ and Docker Compose v2 are required.

## Quick Start

```bash
# 1. Clone the repo
git clone https://github.com/VectorParkarDevOrg/Vector-FinOps-Docker.git
cd Vector-FinOps-Docker

# 2. Build the image (takes 10–20 minutes on first run)
docker build -t vectorfinops:single -f optscale_single/Dockerfile .

# 3. Start the container
cd optscale_single
docker compose up -d

# 4. Open in browser
#    http://<your-server-ip>:8080
```

First boot takes 2–3 minutes while databases initialise. All 46 services start automatically.

## What's Inside

All services run inside one container managed by supervisord:

- **MongoDB 7** — primary data store (replica set)
- **MariaDB 10.11** — relational data (REST API, Auth, Katara)
- **InfluxDB 1.8** — time-series metrics
- **ClickHouse** — analytics
- **RabbitMQ** — message queue
- **Redis** — cache
- **MinIO** — object storage
- **etcd** — service configuration
- **nginx** — reverse proxy (port 80 inside container → 8080 on host)
- **ngui** — React frontend (served via Node)
- **restapi, auth, herald, keeper, diproxy, slacker** — Python/Tornado API services
- **40+ workers and schedulers** — background processing

## Ports

| Host Port | Service |
|-----------|---------|
| 8080      | Web UI + API (nginx) |

All internal service ports stay inside the container.

## Volumes

Persistent data is stored in named Docker volumes:

| Volume | Contents |
|--------|----------|
| `mongo-data` | MongoDB databases |
| `mariadb-data` | MariaDB databases |
| `influxdb-data` | InfluxDB metrics |
| `minio-data` | Object storage |
| `etcd-data` | Service configuration |
| `rabbitmq-data` | Message queue |
| `clickhouse-data` | Analytics data |
| `optscale-logs` | All service logs |

## Configuration

Environment variables in `docker-compose.yml`:

```yaml
environment:
  - KEYCLOAK_SERVER_URL=      # leave empty — Keycloak not used
  - KEYCLOAK_REALM=
  - KEYCLOAK_OAUTH_CLIENT_ID=
  - KEYCLOAK_OAUTH_CLIENT_SECRET=
```

Login with email + password. Create your first user via the Register page at `http://<host>:8080/register`.

## Checking Service Health

```bash
# All services should show RUNNING (configurator shows EXITED — that's correct)
docker exec <container_name> supervisorctl status

# View logs
docker exec <container_name> tail -f /var/log/optscale/restapi.log
docker exec <container_name> tail -f /var/log/optscale/init.log
```

## Upgrading

```bash
# Rebuild image with latest code
docker build -t vectorfinops:single -f optscale_single/Dockerfile .

# Restart container (volumes preserved)
cd optscale_single
docker compose down && docker compose up -d
```

## Branding

White-labelled as **Vector FinOps** by [Parkar Digital](https://www.parkar.in).  
Based on [OptScale](https://github.com/hystax/optscale) by Hystax (Apache 2.0).

## License

Apache License 2.0 — see [LICENSE](../LICENSE) in the repository root.
