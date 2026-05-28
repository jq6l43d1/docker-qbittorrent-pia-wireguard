FROM thrnz/docker-wireguard-pia:latest

# Bake the self-healing healthcheck script into the image. Previously
# bind-mounted from the repo, which broke whenever the orchestrator
# (Komodo) recloned the working tree — the bind captured the old inode
# and silently emptied. The /host-signal bind that talks to the host
# watchdog is orthogonal and stays in compose.yaml.
COPY pia-healthcheck/healthcheck.sh /pia-healthcheck/healthcheck.sh
RUN chmod 0755 /pia-healthcheck/healthcheck.sh
