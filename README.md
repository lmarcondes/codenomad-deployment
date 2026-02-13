# CodeNomad + OpenCode Docker Deployment

Docker Compose deployment for running [CodeNomad](https://github.com/NeuralNomadsAI/CodeNomad) and [OpenCode](https://opencode.ai/) as a self-hosted service. CodeNomad provides a browser-based multi-session workspace on top of OpenCode, an open-source AI coding agent.

## Prerequisites

- [Docker](https://docs.docker.com/get-docker/) 24+ with the Compose plugin
- An API key for at least one LLM provider (Anthropic, OpenAI, etc.)

## Quick Start

```bash
# 1. Clone the repo and enter the directory
git clone <repo-url> && cd codenomad-deployment

# 2. Create your environment file
cp .env.example .env

# 3. Edit .env — set a password and at least one API key
#    CODENOMAD_SERVER_PASSWORD=<pick-a-strong-password>
#    ANTHROPIC_API_KEY=sk-ant-...

# 4. Place project code in the workspaces directory
cp -r /path/to/my-project ./workspaces/

# 5. Build and start
docker compose up -d

# 6. Open the UI
open http://localhost:9899
```

Log in with the username and password you configured in `.env` (defaults to `admin` / the value of `CODENOMAD_SERVER_PASSWORD`).

## Architecture

```
 Browser
   |
   | HTTP :9899
   v
┌──────────────────────────────────────────┐
│  Docker Container                        │
│                                          │
│  ┌────────────┐    spawns    ┌────────┐  │
│  │ CodeNomad  │ ──────────>  │OpenCode│  │
│  │ Server     │ <──────────  │Sessions│  │
│  │ (Fastify)  │   HTTP API   │  (N)   │  │
│  └────────────┘              └────────┘  │
│        │                         │       │
│        └─────────┬───────────────┘       │
│                  │                       │
│            /workspaces (bind mount)      │
└──────────────────────────────────────────┘
                   │
            Host filesystem
```

- **CodeNomad** is a Node.js/Fastify server that serves the web UI and manages OpenCode sessions. It listens on port `9899` over HTTP.
- **OpenCode** is the AI coding agent. CodeNomad spawns one process per session; each session talks to your configured LLM provider to read, write, and refactor code.
- **Workspaces** are bind-mounted from the host so OpenCode has direct read/write access to your project files.

## Project Structure

```
codenomad-deployment/
├── Dockerfile                 # Multi-stage build (Node 22, OpenCode CLI, CodeNomad server)
├── docker-compose.yml         # Service definition, ports, volumes, resource limits
├── .env.example               # Template — copy to .env and fill in secrets
├── .dockerignore
├── .gitignore
├── config/
│   ├── opencode.json          # OpenCode global config (permissions, compaction, server)
│   └── codenomad-config.json  # CodeNomad server defaults
├── scripts/
│   └── entrypoint.sh          # Startup script: validates config, writes auth, launches server
└── workspaces/                # Bind-mounted host directory for project code
    └── .gitkeep
```

## Configuration

All runtime configuration is done through environment variables in the `.env` file. The full list is documented in [`.env.example`](.env.example).

### Authentication

| Variable | Description | Default |
|---|---|---|
| `CODENOMAD_SERVER_USERNAME` | Username for the web UI login | `admin` |
| `CODENOMAD_SERVER_PASSWORD` | Password for the web UI login | *(required)* |
| `CODENOMAD_SKIP_AUTH` | Set to `true` to disable authentication entirely | `false` |

> **Warning:** Only set `CODENOMAD_SKIP_AUTH=true` if the container is behind a trusted perimeter (VPN, SSO proxy, private network).

### LLM Providers

Set at least one API key. The entrypoint script writes these into OpenCode's `auth.json` on every container start.

| Variable | Provider |
|---|---|
| `ANTHROPIC_API_KEY` | Anthropic (Claude) |
| `OPENAI_API_KEY` | OpenAI (GPT) |
| `OPENCODE_API_KEY` | OpenCode Zen (curated models) |
| `OPENROUTER_API_KEY` | OpenRouter (multi-provider gateway) |

### Server Settings

| Variable | Description | Default |
|---|---|---|
| `CODENOMAD_HTTP_PORT` | Host port the web UI is exposed on | `9899` |
| `WORKSPACES_PATH` | Host path mounted as `/workspaces` in the container | `./workspaces` |
| `CODENOMAD_UNRESTRICTED_ROOT` | Allow browsing the full container filesystem | `false` |

### OpenCode Internals

| Variable | Description | Default |
|---|---|---|
| `OPENCODE_SERVER_PASSWORD` | Password for the internal OpenCode HTTP API | *(empty)* |
| `OPENCODE_SERVER_USERNAME` | Username for the internal OpenCode HTTP API | `opencode` |

These protect the OpenCode server API that CodeNomad talks to. Because communication happens entirely inside the container, leaving these empty is safe for most setups.

## Volumes

The compose file defines three mounts:

| Mount | Type | Purpose |
|---|---|---|
| `./workspaces` -> `/workspaces` | Bind mount | Your project source code. OpenCode reads and writes here. |
| `opencode-data` | Named volume | Persists OpenCode session history and auth between restarts. |
| `codenomad-config` | Named volume | Persists CodeNomad runtime configuration. |

### Optional Mounts

Uncomment these lines in `docker-compose.yml` if needed:

```yaml
# SSH keys for git clone/push over SSH
- "${HOME}/.ssh:/home/codeuser/.ssh:ro"

# Git identity for commits made inside the container
- "${HOME}/.gitconfig:/home/codeuser/.gitconfig:ro"
```

## Resource Limits

Default limits are set in `docker-compose.yml` under `deploy.resources`:

| Resource | Limit | Reservation |
|---|---|---|
| Memory | 4 GB | 512 MB |
| CPUs | 2.0 | 0.5 |

Each active OpenCode session is a separate Node.js process. If you run many concurrent sessions, increase these limits accordingly.

## Common Operations

### Rebuild after config changes

```bash
docker compose up -d --build
```

### View logs

```bash
docker compose logs -f codenomad
```

### Stop the service

```bash
docker compose down
```

### Stop and remove all data (sessions, config)

```bash
docker compose down -v
```

### Change the exposed port

Set `CODENOMAD_HTTP_PORT` in `.env`:

```
CODENOMAD_HTTP_PORT=8080
```

Then restart:

```bash
docker compose up -d
```

### Point to a different workspace directory

```
WORKSPACES_PATH=/home/user/projects
```

## Remote Access

The container binds to `0.0.0.0` inside Docker and exposes port `9899` on the host. For remote access:

1. **Over a LAN or VPN** -- access `http://<host-ip>:9899` directly. Authentication is handled by CodeNomad's built-in login.
2. **Over the internet** -- place a TLS-terminating reverse proxy (Caddy, Nginx, Cloudflare Tunnel, etc.) in front of port `9899`. The container itself serves plain HTTP.

Example with Caddy (run on the host, outside Docker):

```
codenomad.example.com {
    reverse_proxy localhost:9899
}
```

## Customizing OpenCode

The file `config/opencode.json` is baked into the image at build time as the global OpenCode config (`~/.config/opencode/opencode.json`). It ships with:

- All tool permissions set to `allow` (no interactive approval prompts in the headless container).
- Automatic context compaction enabled.
- The OpenCode HTTP server bound to `0.0.0.0:4096` (used internally by CodeNomad).

To add custom models, MCP servers, themes, or agents, edit `config/opencode.json` before building. See the [OpenCode config docs](https://opencode.ai/docs/config/) for the full schema.

Per-project configuration can also be added by placing an `opencode.json` file in the root of any project inside `workspaces/`.

## Troubleshooting

### Container exits immediately

Check logs:

```bash
docker compose logs codenomad
```

Common causes:
- Missing or invalid `CODENOMAD_SERVER_PASSWORD` without `CODENOMAD_SKIP_AUTH=true`.
- Port `9899` already in use on the host. Change `CODENOMAD_HTTP_PORT`.

### OpenCode sessions fail to start

- Verify at least one LLM API key is set in `.env`. The entrypoint prints a warning if none are detected.
- Check that your API key is valid and has sufficient quota.

### Permission denied on workspace files

The container runs as UID/GID `1000`. If your host files are owned by a different user, either:
- `chown -R 1000:1000 ./workspaces`, or
- Adjust the `codeuser` UID/GID in the Dockerfile to match your host user.

### Health check failing

The health check hits `http://127.0.0.1:9899/`. If the server takes longer than 15 seconds to start (large `node_modules`, slow network for UI auto-update), increase the `start-period` in the Dockerfile `HEALTHCHECK` directive.

## License

This deployment configuration is provided as-is. CodeNomad is licensed under [MIT](https://github.com/NeuralNomadsAI/CodeNomad/blob/dev/LICENSE). OpenCode is open source and maintained by [Anomaly](https://anoma.ly).
