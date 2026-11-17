#!/usr/bin/env bash
# Railway start script for Passbolt CE. Prepares the volume, then runs the
# upstream /docker-entrypoint.sh unchanged.
set -eo pipefail

DATA="${PASSBOLT_DATA_DIR:-/data}"
CAKE=/usr/share/php/passbolt/bin/cake
SITE=/etc/nginx/sites-available/nginx-passbolt.conf
log() { echo "[railway] $*"; }
as_www() { su -s /bin/bash -c "$1" www-data; }

# 1. nginx listens on $PORT.
export PORT="${PORT:-8080}"
sed -i "s/__PORT__/${PORT}/g; s/listen \(\[::\]:\)\?[0-9]\+;/listen \1${PORT};/" "$SITE"
nginx -t 2>&1 | tail -1

# 2. Server OpenPGP key and JWT key pair live on the volume. Losing the server
#    key makes every stored secret unreadable, so never keep it in the image.
mkdir -p "$DATA/gpg" "$DATA/jwt"
for d in gpg jwt; do
  if [ ! -L "/etc/passbolt/$d" ]; then
    cp -an "/etc/passbolt/$d/." "$DATA/$d/" 2>/dev/null || true
    rm -rf "/etc/passbolt/$d"
    ln -s "$DATA/$d" "/etc/passbolt/$d"
  fi
done
fix_perms() {
  chown -R www-data:www-data "$DATA/gpg"; chmod 770 "$DATA/gpg"
  find "$DATA/gpg" -type f -exec chmod 640 {} +
  chown -R root:www-data "$DATA/jwt"; chmod 750 "$DATA/jwt"
  find "$DATA/jwt" -type f -exec chmod 640 {} +
}
fix_perms

# 3. Defaults the template doesn't need to ask for.
[ -n "${APP_FULL_BASE_URL:-}" ] || { [ -n "${RAILWAY_PUBLIC_DOMAIN:-}" ] && export APP_FULL_BASE_URL="https://${RAILWAY_PUBLIC_DOMAIN}"; }
export PASSBOLT_KEY_NAME="${PASSBOLT_KEY_NAME:-Passbolt server key}"
export PASSBOLT_KEY_EMAIL="${PASSBOLT_KEY_EMAIL:-passbolt@${RAILWAY_PUBLIC_DOMAIN:-localhost}}"
export PASSBOLT_REGISTRATION_PUBLIC="${PASSBOLT_REGISTRATION_PUBLIC:-false}"
export PASSBOLT_SSL_FORCE="${PASSBOLT_SSL_FORCE:-true}"
# Read the server key fingerprint from the key file, so a later domain or
# email change can't make the lookup by email fail.
if [ -f "$DATA/gpg/serverkey.asc" ] && [ -z "${PASSBOLT_GPG_SERVER_KEY_FINGERPRINT:-}" ]; then
  tmpg="$(mktemp -d)"
  fpr="$(gpg --homedir "$tmpg" --with-colons --import-options show-only --import "$DATA/gpg/serverkey.asc" 2>/dev/null | awk -F: '/^fpr/{print $10; exit}')"; rm -rf "$tmpg"
  [ -n "$fpr" ] && export PASSBOLT_GPG_SERVER_KEY_FINGERPRINT="$fpr" && log "server key $fpr"
fi
log "APP_FULL_BASE_URL=${APP_FULL_BASE_URL:-unset}"

# 4. Wait for the database (Railway starts services in parallel).
if [ -n "${DATASOURCES_DEFAULT_HOST:-}" ]; then
  /usr/bin/wait-for.sh -t 300 "${DATASOURCES_DEFAULT_HOST}:${DATASOURCES_DEFAULT_PORT:-3306}" \
    || log "database not reachable yet, continuing"
fi

# 5. After the app answers: fix JWT permissions and create the first admin.
after_start() {
  for _ in $(seq 1 180); do
    curl -fsS -o /dev/null --max-time 5 "http://127.0.0.1:${PORT}/healthcheck/status.json" && break
    sleep 5
  done
  fix_perms
  [ -n "${PASSBOLT_ADMIN_EMAIL:-}" ] || { log "PASSBOLT_ADMIN_EMAIL is empty: no admin created"; return 0; }
  users="$(as_www "$CAKE passbolt users_index" 2>&1 || true)"
  if echo "$users" | grep -qiF "$PASSBOLT_ADMIN_EMAIL"; then
    link="$(php /railway-setup-link.php)"
    [ -n "$link" ] && log "admin setup is not finished yet. Setup link: $link"
    return 0
  fi
  if echo "$users" | grep -q '@'; then log "users exist; not creating ${PASSBOLT_ADMIN_EMAIL}"; return 0; fi
  log "creating the first administrator ${PASSBOLT_ADMIN_EMAIL}"
  as_www "$CAKE passbolt register_user -u \"\$PASSBOLT_ADMIN_EMAIL\" -f \"\${PASSBOLT_ADMIN_FIRST_NAME:-Admin}\" -l \"\${PASSBOLT_ADMIN_LAST_NAME:-User}\" -r admin" 2>&1 || true
  log "Open the /setup/start/... link above in a browser with the Passbolt extension to finish."
}
after_start &

exec /docker-entrypoint.sh
