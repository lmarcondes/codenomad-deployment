# =============================================================================
# CodeNomad + OpenCode - Docker Deployment
# =============================================================================
# Multi-stage build that installs OpenCode CLI and CodeNomad server into a
# single container. CodeNomad acts as the web-based command center, proxying
# and managing OpenCode sessions.
# =============================================================================

FROM node:22-bookworm-slim

LABEL maintainer="deployment@codenomad"
LABEL description="CodeNomad + OpenCode deployment container"

RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install OpenCode CLI globally
RUN npm install -g opencode-ai

# Install CodeNomad server globally
RUN npm install -g @neuralnomads/codenomad

# Install runtime dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    ca-certificates \
    curl \
    openssh-client \
    jq \
    ripgrep \
    && rm -rf /var/lib/apt/lists/*

# Create non-root user for running the services
RUN groupadd codeuser && \
    useradd --gid codeuser --shell /bin/bash --create-home codeuser

# Create required directories
RUN mkdir -p /home/codeuser/.config/opencode \
             /home/codeuser/.config/codenomad \
             /home/codeuser/.local/share/opencode \
             /workspaces && \
    chown -R codeuser:codeuser /home/codeuser /workspaces

# Copy configuration files
COPY --chown=codeuser:codeuser config/opencode.json /home/codeuser/.config/opencode/opencode.json
COPY --chown=codeuser:codeuser config/codenomad-config.json /home/codeuser/.config/codenomad/config.json

# Copy entrypoint script
COPY --chown=codeuser:codeuser scripts/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Switch to non-root user
USER codeuser
WORKDIR /workspaces

# ---------------------------------------------------------------------------
# Ports:
#   9899 - CodeNomad HTTP server (web UI + API)
# ---------------------------------------------------------------------------
EXPOSE 9899

# Health check: ping the CodeNomad server
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -f http://127.0.0.1:9899/ || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
