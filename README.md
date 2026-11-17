[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/passbolt-1?utm_medium=integration&utm_source=button&utm_campaign=passbolt)

# Passbolt CE on Railway

Railway template for [Passbolt](https://www.passbolt.com/) Community Edition, the open source password manager for teams.

## What it deploys

| Service | Source | State |
|---|---|---|
| **Passbolt** | this repo: `FROM passbolt/passbolt:5.18.0-1-ce@sha256:b853bf94…6012e2f` plus a small start script | volume at `/data` (server OpenPGP key, JWT key pair) |
| **MariaDB** | `mariadb:10.11.19@sha256:7d829180…760f20` (the version in Passbolt's own Compose file) | volume at `/var/lib/mysql` |

Passbolt serves plain HTTP on `PORT` (8080) behind Railway's HTTPS edge, with `PASSBOLT_SSL_FORCE=true`. Its health check is `/healthcheck/status.json`.

The start script (`rootfs/railway-start.sh`) adds only what Railway needs, then runs upstream's `/docker-entrypoint.sh`:

- moves `/etc/passbolt/gpg` and `/etc/passbolt/jwt` onto the volume. **Back up `/data/gpg`**: without the server key, nothing stored in Passbolt can be decrypted;
- sets `APP_FULL_BASE_URL` from the Railway domain if it's empty, and reads the server key fingerprint from the key file;
- waits for MariaDB;
- once the app answers, creates the first administrator (`PASSBOLT_ADMIN_EMAIL`) and prints the one-time `/setup/start/…` link in the deploy logs. Until setup is finished, every restart prints the link again while it is still valid (10 days).

## Variables

| Service | Variable | Default |
|---|---|---|
| Passbolt | `PASSBOLT_ADMIN_EMAIL` | **asked at deploy**: the first administrator's email |
| Passbolt | `APP_FULL_BASE_URL` | `https://${{RAILWAY_PUBLIC_DOMAIN}}` (change it if you add a custom domain) |
| Passbolt | `DATASOURCES_DEFAULT_*` | references to the MariaDB service, private network |
| Passbolt | `PORT` | `8080` |
| MariaDB | `MARIADB_PASSWORD`, `MARIADB_ROOT_PASSWORD` | generated per deployment (`${{secret(32)}}`) |
| MariaDB | `MARIADB_DATABASE`, `MARIADB_USER` | `passbolt` |

Optional, add them to the Passbolt service when you need them: `EMAIL_TRANSPORT_DEFAULT_HOST`, `EMAIL_TRANSPORT_DEFAULT_PORT`, `EMAIL_TRANSPORT_DEFAULT_USERNAME`, `EMAIL_TRANSPORT_DEFAULT_PASSWORD`, `EMAIL_TRANSPORT_DEFAULT_TLS`, `EMAIL_DEFAULT_FROM` (or set SMTP in Passbolt's admin pages), `PASSBOLT_ADMIN_FIRST_NAME` and `PASSBOLT_ADMIN_LAST_NAME` (default `Admin User`). Every option: [Passbolt environment variables](https://www.passbolt.com/docs/hosting/configure/environment-reference/).

## First login

1. Install the Passbolt browser extension (Chrome, Firefox, Edge, Safari).
2. Open the Passbolt service's **Deploy Logs** and find `[railway] … Setup link: https://…/setup/start/…` (or the `register_user` output just after the first boot).
3. Open the link, create your passphrase and download the recovery kit. Keep it: it is the only copy of your private key.

## Updates

The template builds from this repo's `main` branch. When we bump the pinned Passbolt image, Railway shows an "update available" notice in your project, and you choose when to apply it. Read [CHANGELOG.md](CHANGELOG.md) first: breaking changes are listed at the top of each entry. Passbolt runs its database migrations on start.

## Licence

The wrapper files in this repo are MIT. Passbolt is AGPL-3.0 ([passbolt/passbolt_api](https://github.com/passbolt/passbolt_api)).
