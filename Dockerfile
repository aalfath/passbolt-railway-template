# Passbolt CE for Railway.
# Upstream image pinned by version and digest. Bump both together and add a
# CHANGELOG.md entry: a merge to main notifies everyone who deployed the template.
FROM passbolt/passbolt:5.18.0-1-ce@sha256:b853bf94c70bfb9a35b25de79ef7ba91c42b4fcee04693e47b690d66f6012e2f

# Plain HTTP on $PORT (Railway's edge terminates TLS), real client IP and the
# https flag from the edge's headers, and a sane worker count for a container.
COPY rootfs/railway-proxy.conf /etc/nginx/conf.d/railway-proxy.conf
COPY rootfs/railway-start.sh rootfs/railway-setup-link.php /
RUN set -eux; \
    site=/etc/nginx/sites-available/nginx-passbolt.conf; \
    sed -i -e 's|^  listen 80;|  listen __PORT__;|' \
           -e 's|^  listen \[::\]:80;|  listen [::]:__PORT__;|' \
           -e 's|^  include /etc/nginx/snippets/passbolt-ssl.conf;|  # TLS ends at the Railway edge|' "$site"; \
    grep -q '__PORT__' "$site"; ! grep -q 'passbolt-ssl.conf' "$site"; \
    sed -i -e 's|^worker_processes .*|worker_processes 2;|' -e 's|^worker_cpu_affinity|#worker_cpu_affinity|' /etc/nginx/nginx.conf; \
    sed -i 's|^fastcgi_param  HTTPS .*|fastcgi_param  HTTPS              $railway_https if_not_empty;|' /etc/nginx/fastcgi_params; \
    grep -q railway_https /etc/nginx/fastcgi_params; \
    chmod 0755 /railway-start.sh; bash -n /railway-start.sh

EXPOSE 8080
CMD ["/railway-start.sh"]
