#!/bin/sh
# Run the live MySQL client tests: initialize a throwaway MySQL
# server (fresh datadir under /tmp, loopback 127.0.0.1:13306 only),
# create the test accounts, warm the caching_sha2 credential cache
# for cache_warm with one login through the official client, run
# tests/mysql_client_live.sla, then shut the server down.
#
# NOT part of the default suites — it needs mysqld and the mysql
# client installed (apt: mysql-server). Run from the sci repo root
# with the worktree's `sa` on PATH and SA_PLUGIN_DEV=1, e.g.:
#   PATH=$PWD/zig-out/bin:$PATH sh tests/run_mysql_live_tests.sh
set -e
cd "$(dirname "$0")/.."

PORT=13306
DATA=/tmp/sa_mysql_live_data
SOCK=/tmp/sa_mysql_live.sock
PIDF=/tmp/sa_mysql_live.pid
ERRLOG=/tmp/sa_mysql_live_err.log

cleanup() {
    if [ -f "$PIDF" ]; then
        kill "$(cat "$PIDF")" 2>/dev/null || true
        for i in 1 2 3 4 5 6 7 8 9 10; do
            [ -f "$PIDF" ] || break
            sleep 1
        done
    fi
    rm -rf "$DATA" "$SOCK" "$PIDF"
}
trap cleanup EXIT
cleanup

# Note: MySQL 8.0 ships mysql_native_password enabled by default and has no
# --mysql-native-password startup option (that toggle exists in 8.4+; a naive
# grep of --help false-matches mysql-native-password-proxy-users). The setup
# SQL below uses IDENTIFIED WITH mysql_native_password, which fails loudly
# if the plugin is ever unavailable -- no silent fallback.

mysqld --initialize-insecure --datadir="$DATA" --user=root --log-error="$ERRLOG"
mysqld --datadir="$DATA" --user=root --port=$PORT --bind-address=127.0.0.1 \
    --socket="$SOCK" --pid-file="$PIDF" --log-error="$ERRLOG" \
    --skip-name-resolve &
for i in $(seq 1 60); do
    if mysqladmin --socket="$SOCK" -u root ping >/dev/null 2>&1; then
        break
    fi
    sleep 1
done
mysqladmin --socket="$SOCK" -u root ping >/dev/null

mysql --socket="$SOCK" -u root <<'SQL'
CREATE DATABASE sa_mysql_live;
CREATE USER 'native_tester'@'%' IDENTIFIED WITH mysql_native_password BY 'native_pw';
CREATE USER 'cache_warm'@'%' IDENTIFIED WITH caching_sha2_password BY 'cache_pw';
CREATE USER 'cache_cold'@'%' IDENTIFIED WITH caching_sha2_password BY 'cache_pw';
GRANT ALL PRIVILEGES ON sa_mysql_live.* TO 'native_tester'@'%';
GRANT ALL PRIVILEGES ON sa_mysql_live.* TO 'cache_warm'@'%';
GRANT ALL PRIVILEGES ON sa_mysql_live.* TO 'cache_cold'@'%';
SQL

# Warm the caching_sha2 fast-path cache for cache_warm only. The
# official client performs full auth (RSA) here; afterwards the
# server can answer our client's fast-path scramble. cache_cold is
# deliberately never logged in, so its first login (by the SLA test)
# still demands full auth.
mysql -h 127.0.0.1 -P $PORT -u cache_warm -pcache_pw -e "SELECT 1" >/dev/null 2>&1

SA_PLUGIN_DEV=1 timeout 300 sa test tests/mysql_client_live.sla
echo "mysql live tests: PASS"
