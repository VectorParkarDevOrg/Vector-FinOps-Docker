#!/bin/bash
# Vector FinOps — Single Container Entrypoint
# Handles first-time DB initialization, then hands off to supervisord.
set -e

LOG_DIR=/var/log/optscale
mkdir -p "$LOG_DIR"
# All services need to write logs here
chmod 777 "$LOG_DIR"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_DIR/init.log"; }

log "=== Vector FinOps Single Container starting ==="

# Ensure MariaDB socket directory exists (required before mariadbd starts)
mkdir -p /run/mysqld /var/run/mysqld
chown mysql:mysql /run/mysqld /var/run/mysqld 2>/dev/null || true

# ── MariaDB: first-time initialization ───────────────────────────────────────
if [ ! -d /var/lib/mysql/mysql ]; then
    log "MariaDB: first-time initialization..."

    mariadb-install-db --user=mysql --datadir=/var/lib/mysql --skip-test-db \
        >> "$LOG_DIR/init.log" 2>&1 || \
    mysql_install_db --user=mysql --datadir=/var/lib/mysql \
        >> "$LOG_DIR/init.log" 2>&1 || true

    # Start temporarily without networking
    /usr/sbin/mariadbd --user=mysql --skip-networking \
        --pid-file=/var/run/mysqld/mysqld.pid &
    MYSQL_PID=$!

    log "MariaDB: waiting for socket..."
    for i in $(seq 1 60); do
        mysql -u root --socket=/var/run/mysqld/mysqld.sock \
            -e "SELECT 1" >/dev/null 2>&1 && break
        sleep 1
    done

    log "MariaDB: setting root password..."
    # Use IDENTIFIED VIA syntax (MariaDB 10.4+) to override dual-auth and set
    # a proper mysql_native_password hash so TCP connections from 127.0.0.1 work.
    mysql -u root --socket=/var/run/mysqld/mysqld.sock <<-EOSQL 2>/dev/null || true
        ALTER USER 'root'@'localhost' IDENTIFIED VIA mysql_native_password USING PASSWORD('my-password-01');
        CREATE USER IF NOT EXISTS 'root'@'127.0.0.1' IDENTIFIED BY 'my-password-01';
        GRANT ALL PRIVILEGES ON *.* TO 'root'@'127.0.0.1' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
EOSQL

    log "MariaDB: shutting down init instance..."
    mysqladmin --socket=/var/run/mysqld/mysqld.sock \
        -u root -p'my-password-01' shutdown 2>/dev/null || \
    kill "$MYSQL_PID" 2>/dev/null || true
    wait "$MYSQL_PID" 2>/dev/null || true
    sleep 2
    log "MariaDB: initialization complete."
fi

# ── MongoDB: first-time initialization ───────────────────────────────────────
if [ ! -d /data/db/admin ]; then
    log "MongoDB: first-time initialization..."

    mkdir -p /data/configdb /data/db
    printf '%s' 'secureShardingKeyFFFDDa129' > /data/configdb/key.txt
    chmod 400 /data/configdb/key.txt
    chown -R mongodb:mongodb /data/db /data/configdb

    # Start without auth for initialization
    # Use /tmp for log so mongodb user can always write to it
    su -s /bin/bash -c "mongod \
        --replSet mongo \
        --bind_ip_all \
        --dbpath /data/db \
        --port 27017 \
        --storageEngine wiredTiger \
        --wiredTigerCacheSizeGB 0.25 \
        --logpath /tmp/mongod-init.log \
        --fork" mongodb 2>>"$LOG_DIR/init.log"

    log "MongoDB: waiting for startup..."
    for i in $(seq 1 60); do
        mongosh --quiet --eval "db.adminCommand({ping:1})" >/dev/null 2>&1 && break
        sleep 2
    done

    log "MongoDB: initializing replica set..."
    mongosh --quiet --eval "
        try {
            rs.status();
        } catch(e) {
            rs.initiate({_id:'mongo', members:[{_id:0, host:'127.0.0.1:27017'}]});
        }
    " 2>>"$LOG_DIR/init.log" || true
    sleep 8

    log "MongoDB: creating admin user..."
    mongosh admin --quiet --eval "
        try {
            db.createUser({user:'root', pwd:'SecurePassword-01-02', roles:['root']});
            print('Created successfully');
        } catch(e) { print('Note: ' + e); }
    " 2>>"$LOG_DIR/init.log" || true

    log "MongoDB: shutting down init instance..."
    mongosh admin --quiet \
        --eval "db.adminCommand({shutdown:1, force:true})" 2>/dev/null || true
    sleep 3
    # Force kill if still running
    pkill -f "mongod.*replSet" 2>/dev/null || true
    sleep 2
    log "MongoDB: initialization complete."
fi

# ── Start cron daemon ─────────────────────────────────────────────────────────
log "Starting cron daemon..."
cron 2>>"$LOG_DIR/cron.log" || service cron start 2>/dev/null || true

# ── Hand off to supervisord ───────────────────────────────────────────────────
log "Starting supervisord (managing all services)..."
exec /usr/bin/supervisord -n -c /etc/supervisor/supervisord.conf
