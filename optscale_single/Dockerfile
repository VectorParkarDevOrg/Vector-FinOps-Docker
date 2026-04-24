# ============================================================================
# Vector FinOps — Single Container (All services in one Docker image)
# Build context: VectorFinOps-Docker/
# Build: docker build -f optscale_single/Dockerfile -t vectorfinops:single .
# ============================================================================

# ── Stage 1: Build ngui (React SPA + Node.js BFF) ───────────────────────────
FROM node:22.16.0-alpine3.21 AS ngui-builder

RUN npm install -g pnpm@10.12.1
ENV NODE_ENV=production

WORKDIR /build
COPY ngui/ .
RUN pnpm install --frozen-lockfile --ignore-scripts && \
    pnpm run -r build && \
    pnpm deploy --filter=server --prod ./prod/server && \
    ./prod/server/scripts/prune_node_modules.sh && \
    rm -rf ./ui/node_modules

# ── Stage 2: Build jira_ui ───────────────────────────────────────────────────
FROM node:18.14.2-alpine3.16 AS jiraui-builder

WORKDIR /build/ui
COPY jira_ui/ui/package*.json ./
RUN npm ci --ignore-scripts --legacy-peer-deps
COPY jira_ui/ui/ ./
RUN npm run build && rm -rf node_modules

WORKDIR /build/server
COPY jira_ui/server/package*.json ./
RUN npm ci --ignore-scripts
COPY jira_ui/server/ ./
# Patch port to be configurable via PORT env var (default 4000, we set 4001 at runtime)
RUN sed -i 's/const PORT = 4000/const PORT = parseInt(process.env.PORT) || 4000/' index.js
RUN ./scripts/prune_node_modules.sh

# ── Stage 3: Production monolith ─────────────────────────────────────────────
FROM python:3.12-slim-bookworm

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONPATH=/usr/src/app \
    PYTHONUNBUFFERED=1

# ── Core system packages ─────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    supervisor cron curl wget gnupg lsb-release ca-certificates \
    nginx procps libsodium-dev sendmail \
    mariadb-server mariadb-client \
    redis-server \
    && rm -rf /var/lib/apt/lists/*

# ── MongoDB 7.0 ──────────────────────────────────────────────────────────────
RUN curl -fsSL https://www.mongodb.org/static/pgp/server-7.0.asc \
      | gpg --dearmor -o /usr/share/keyrings/mongodb-server-7.0.gpg && \
    echo "deb [ signed-by=/usr/share/keyrings/mongodb-server-7.0.gpg ] \
      https://repo.mongodb.org/apt/debian bookworm/mongodb-org/7.0 main" \
      > /etc/apt/sources.list.d/mongodb-org-7.0.list && \
    apt-get update && apt-get install -y --no-install-recommends mongodb-org && \
    rm -rf /var/lib/apt/lists/*

# ── RabbitMQ (Debian Bookworm default — 3.x, sufficient for OptScale) ────────
RUN apt-get update && apt-get install -y --no-install-recommends \
    rabbitmq-server && \
    rm -rf /var/lib/apt/lists/*

# ── ClickHouse ────────────────────────────────────────────────────────────────
RUN curl -fsSL 'https://packages.clickhouse.com/rpm/lts/repodata/repomd.xml.key' \
      | gpg --dearmor -o /usr/share/keyrings/clickhouse-keyring.gpg && \
    echo "deb [signed-by=/usr/share/keyrings/clickhouse-keyring.gpg] \
      https://packages.clickhouse.com/deb stable main" \
      > /etc/apt/sources.list.d/clickhouse.list && \
    apt-get update && apt-get install -y --no-install-recommends \
      clickhouse-server clickhouse-client && \
    rm -rf /var/lib/apt/lists/*

# ── InfluxDB 1.8.10 ───────────────────────────────────────────────────────────
RUN wget -q https://dl.influxdata.com/influxdb/releases/influxdb_1.8.10_amd64.deb && \
    dpkg -i influxdb_1.8.10_amd64.deb && \
    rm -f influxdb_1.8.10_amd64.deb

# ── etcd v3.5.18 (v2 API enabled) ────────────────────────────────────────────
RUN ETCD_VER=v3.5.18 && \
    wget -q "https://github.com/etcd-io/etcd/releases/download/${ETCD_VER}/etcd-${ETCD_VER}-linux-amd64.tar.gz" && \
    mkdir -p /opt/etcd && \
    tar xzf "etcd-${ETCD_VER}-linux-amd64.tar.gz" -C /opt/etcd --strip-components=1 && \
    ln -sf /opt/etcd/etcd /usr/local/bin/etcd && \
    ln -sf /opt/etcd/etcdctl /usr/local/bin/etcdctl && \
    rm -f "etcd-${ETCD_VER}-linux-amd64.tar.gz"

# ── MinIO binary ──────────────────────────────────────────────────────────────
RUN mkdir -p /opt/minio && \
    wget -q "https://dl.min.io/server/minio/release/linux-amd64/minio" \
      -O /opt/minio/minio && \
    chmod +x /opt/minio/minio && \
    ln -sf /opt/minio/minio /usr/local/bin/minio

# ── Node.js 22 (for ngui + jira_ui runtime) ──────────────────────────────────
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── uv (Python package manager, used by all Python services) ─────────────────
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin sh

# ── Source code ───────────────────────────────────────────────────────────────
WORKDIR /usr/src/app

COPY tools               tools
COPY optscale_client     optscale_client
COPY auth                auth
COPY rest_api            rest_api
COPY keeper              keeper
COPY herald              herald
COPY insider             insider
COPY metroculus          metroculus
COPY katara              katara
COPY bi_exporter         bi_exporter
COPY bumischeduler       bumischeduler
COPY bumiworker          bumiworker
COPY diproxy             diproxy
COPY diworker            diworker
COPY gemini              gemini
COPY risp                risp
COPY trapper             trapper
COPY subspector          subspector
COPY jira_bus            jira_bus
COPY slacker             slacker
COPY docker_images       docker_images

# /src is the WORKDIR for slacker and diworker in their original Dockerfiles
RUN ln -sf /usr/src/app /src

# ── uv sync for all Python services ──────────────────────────────────────────
RUN uv --project auth sync --locked --no-dev && \
    uv --project rest_api sync --locked --no-dev && \
    uv --project keeper sync --locked --no-dev && \
    uv --project herald sync --locked --no-dev && \
    uv --project insider/insider_api sync --locked --no-dev && \
    uv --project insider/insider_scheduler sync --locked --no-dev && \
    uv --project insider/insider_worker sync --locked --no-dev && \
    uv --project metroculus/metroculus_api sync --locked --no-dev && \
    uv --project metroculus/metroculus_scheduler sync --locked --no-dev && \
    uv --project metroculus/metroculus_worker sync --locked --no-dev && \
    uv --project katara/katara_service sync --locked --no-dev && \
    uv --project katara/katara_worker sync --locked --no-dev && \
    uv --project bi_exporter sync --locked --no-dev && \
    uv --project bumischeduler sync --locked --no-dev && \
    uv --project bumiworker sync --locked --no-dev && \
    uv --project diproxy sync --locked --no-dev && \
    uv --project gemini/gemini_scheduler sync --locked --no-dev && \
    uv --project gemini/gemini_worker sync --locked --no-dev && \
    uv --project risp/risp_scheduler sync --locked --no-dev && \
    uv --project risp/risp_worker sync --locked --no-dev && \
    uv --project trapper/trapper_scheduler sync --locked --no-dev && \
    uv --project trapper/trapper_worker sync --locked --no-dev && \
    uv --project subspector sync --locked --no-dev && \
    uv --project jira_bus sync --locked --no-dev

# slacker and diworker use WORKDIR=/src
RUN cd /src && \
    uv --project diworker sync --locked --no-dev && \
    uv --project slacker sync --locked --no-dev

# Generate API specs (required for proper Swagger/OpenAPI handling)
RUN uv --project auth run python -u auth/auth_server/write_spec.py && \
    uv --project rest_api run python -u rest_api/rest_api_server/write_spec.py

# ── Patch slacker: hardcoded port 80 conflicts with nginx ────────────────────
RUN sed -i \
        -e '/LOG\.info("start listening on port %d", 80)/i\    SLACKER_PORT = int(os.environ.get("SLACKER_PORT", 8960))' \
        -e 's/LOG\.info("start listening on port %d", 80)/LOG.info("start listening on port %d", SLACKER_PORT)/' \
        -e 's/tornado_app\.listen(80, decompress_request=True)/tornado_app.listen(SLACKER_PORT, decompress_request=True)/' \
        /usr/src/app/slacker/slacker_server/server.py

# ── Patch herald: service sendmail start exits 1 when already running ────────
RUN sed -i \
        's/subprocess.run("service sendmail start", shell=True, check=True)/subprocess.run("service sendmail start", shell=True, check=False)/' \
        /usr/src/app/herald/run.py

# ── pip install for docker_images services (share system Python) ──────────────
# All services set PYTHONPATH=/usr/src/app so optscale_client packages
# are importable without pip -e installs.
RUN pip install --no-cache-dir \
    kombu==5.3.4 \
    pymongo==4.6.3 \
    currency-symbols==2.0.3 \
    influxdb==4.1.1 \
    mysql-connector-python==9.1.0 \
    "SQLAlchemy==1.3.24" \
    retrying==1.4.1 \
    pyyaml==6.0.1 \
    pika==1.1.0 \
    "boto3==1.34.7" \
    "urllib3==2.5" \
    pytz==2023.3.post1 \
    clickhouse-connect==0.8.15 \
    aio-pika==9.5.5 \
    tenacity==9.1.2 && \
    pip install --no-cache-dir \
    -e optscale_client/config_client \
    -e optscale_client/rest_api_client \
    -e optscale_client/herald_client \
    -e optscale_client/auth_client \
    -e optscale_client/report_client \
    -e optscale_client/insider_client \
    -e optscale_client/slacker_client \
    -e optscale_client/subspector_async_client \
    -e tools/optscale_time \
    -e tools/cloud_adapter

# ── ngui runtime artifacts ────────────────────────────────────────────────────
COPY --from=ngui-builder /build/prod/server/dist        /usr/src/app/server/dist
COPY --from=ngui-builder /build/prod/server/node_modules /usr/src/app/server/node_modules
COPY --from=ngui-builder /build/ui/build                /usr/src/app/ui/build
COPY --from=ngui-builder /build/prepare-and-run.sh      /usr/src/app/prepare-and-run.sh
RUN chmod +x /usr/src/app/prepare-and-run.sh

# ── jira_ui runtime artifacts ─────────────────────────────────────────────────
COPY --from=jiraui-builder /build/ui     /usr/src/app/jira_ui/ui
COPY --from=jiraui-builder /build/server /usr/src/app/jira_ui/server

# ── Config files ──────────────────────────────────────────────────────────────
COPY optscale_single/nginx.conf              /etc/nginx/nginx.conf
COPY optscale_single/supervisord.conf        /etc/supervisor/conf.d/optscale.conf
COPY optscale_single/entrypoint.sh           /entrypoint.sh
COPY optscale_single/etcd-config             /config/etcd-config
COPY optscale_single/crontab.txt             /etc/cron.d/optscale
COPY optscale_single/mariadb.cnf             /etc/mysql/conf.d/optscale.cnf
COPY optscale_single/influxdb.conf           /etc/influxdb/influxdb.conf
COPY optscale_single/rabbitmq.conf           /etc/rabbitmq/rabbitmq.conf
COPY optscale_single/clickhouse-config.xml   /etc/clickhouse-server/config.xml
COPY optscale_single/clickhouse-users.xml    /etc/clickhouse-server/users.xml
COPY optscale-deploy/docker/rabbitmq-plugins /etc/rabbitmq/enabled_plugins
COPY optscale-deploy/docker/rabbit-definitions.json /etc/rabbitmq/definitions.json

# ── Directory setup and permissions ──────────────────────────────────────────
RUN chmod +x /entrypoint.sh && \
    chmod 600 /etc/cron.d/optscale && \
    # Data directories
    mkdir -p /data/db /data/configdb && \
    mkdir -p /var/lib/influxdb /opt/minio-data /default.etcd && \
    mkdir -p /var/log/optscale /var/log/supervisor && \
    # Email template mount points
    mkdir -p /optscale/email_templates /optscale/template_filters && \
    # bi-exporter data
    mkdir -p /usr/src/app/bi_exporter/bi && \
    # gemini cache
    mkdir -p /usr/src/app/gemini_worker/cache && \
    # MongoDB permissions
    chown -R mongodb:mongodb /data/db /data/configdb && \
    # nginx: remove default site
    rm -f /etc/nginx/sites-enabled/default && \
    # RabbitMQ: add user to rabbitmq group if exists
    (getent group rabbitmq > /dev/null && usermod -aG rabbitmq root) || true

VOLUME ["/data/db", "/var/lib/mysql", "/var/lib/influxdb", "/opt/minio-data", "/default.etcd", "/var/lib/rabbitmq", "/var/lib/clickhouse"]

EXPOSE 80

ENTRYPOINT ["/entrypoint.sh"]
