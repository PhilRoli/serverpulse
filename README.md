# ServerPulse

Menu bar app showing the health of your Docker servers: containers grouped by compose project, CPU / RAM / disk, and notifications when something goes down. Each server runs a tiny agent (`agent/`).

## Installation

### Homebrew

```bash
brew tap PhilRoli/tap
brew install --cask serverpulse
```

ServerPulse is ad-hoc signed (not notarized). On first launch, right-click the app in Finder and choose "Open" to bypass Gatekeeper, or run:

```bash
xattr -dr com.apple.quarantine /Applications/ServerPulse.app
```

### Agent

On each server (Linux + Docker compose):

```bash
ssh user@host 'mkdir -p /opt/apps/metrics-agent && cd /opt/apps/metrics-agent && echo "METRICS_TOKEN=$(openssl rand -hex 32)" > .env'
./agent/deploy.sh user@host
```

`deploy.sh` syncs the agent, sets `DOCKER_GID`, runs `docker compose up -d --build` and checks `/health`. The agent listens on `127.0.0.1:4099`; put a TLS reverse proxy in front, e.g. Caddy:

```
metrics.example.com {
    reverse_proxy localhost:4099
}
```

Then in ServerPulse → Preferences add the server with URL `https://metrics.example.com/metrics` and the token from `.env`.

The agent reads `/proc`, `statvfs` on the host root (read-only mount) and `GET /containers/json` on the Docker socket. Socket access is root-equivalent: the container runs as an unprivileged user with a read-only filesystem, but only deploy it on hosts you control.

## How it works

- `GET /metrics` (Bearer token) returns host metrics and container state/health as JSON (`version: 2`).
- The app polls every 15–120 s, keeps the last data when a poll fails and marks it stale after two failures; a rejected token stops polling until it's changed.
- Menu bar: icon only when all is well, a red count for down/unhealthy containers or disk/RAM over threshold, an orange `!` when an agent is unreachable.
- Tokens are stored in the login Keychain via `/usr/bin/security`.

## Development

- Build + install locally: `./rebuild.sh` (installs to /Applications, ad-hoc signed).
- Tests: `swift test` and `python3 -m unittest discover -s agent`. Lint: `swiftlint --strict`.
- Release: push a tag `vX.Y.Z`. The Release workflow builds a universal app, publishes `ServerPulse-X.Y.Z.app.zip` and updates `Casks/serverpulse.rb` in `PhilRoli/homebrew-tap` (needs the `HOMEBREW_TAP_TOKEN` repo secret).
- Regenerate the icon: `scripts/make-icon.sh`.

## License

MIT
