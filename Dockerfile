FROM debian:bookworm-slim
ARG WARP_VERSION=2026.7.1377.0
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl gnupg dbus socat tini \
    && curl -fsSL https://pkg.cloudflareclient.com/pubkey.gpg | gpg --dearmor -o /usr/share/keyrings/cloudflare-warp.gpg \
    && echo 'deb [signed-by=/usr/share/keyrings/cloudflare-warp.gpg] https://pkg.cloudflareclient.com/ bookworm main' > /etc/apt/sources.list.d/cloudflare-warp.list \
    && apt-get update && apt-get install -y --no-install-recommends "cloudflare-warp=${WARP_VERSION}" \
    && rm -rf /var/lib/apt/lists/*
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod 755 /usr/local/bin/entrypoint.sh
VOLUME ["/var/lib/cloudflare-warp"]
EXPOSE 1080/tcp
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
CMD ["serve"]
