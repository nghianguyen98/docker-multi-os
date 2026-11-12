# docker-multi-os

One-command installer for **Docker Engine + Compose v2** on a fresh Linux server, using Docker's official repositories.

| Distro | Versions tested | Arch |
|---|---|---|
| Ubuntu | 24.04 | amd64, arm64 |
| Debian | 12 | amd64, arm64 |
| CentOS Stream | 9 | amd64, arm64 |
| Rocky / AlmaLinux / RHEL / Fedora | same code path as CentOS, not regularly tested | amd64, arm64 |

> macOS is not scripted: install [Docker Desktop](https://www.docker.com/products/docker-desktop/), OrbStack or Colima.

## Quick start

```bash
git clone https://github.com/nghianguyen98/docker-multi-os.git
cd docker-multi-os
sudo ./install_docker.sh -y
```

Or without git:

```bash
curl -fsSL https://raw.githubusercontent.com/nghianguyen98/docker-multi-os/main/install_docker.sh -o install_docker.sh
less install_docker.sh          # always review before running as root
sudo bash install_docker.sh -y
```

## Options

| Flag | Description |
|---|---|
| `-y`, `--yes` | Skip confirmation prompt |
| `--no-compose` | Do not install the buildx / compose plugins |
| `--no-daemon-conf` | Do not write `/etc/docker/daemon.json` |
| `--portainer` | Also deploy Portainer CE (LTS) in `/opt/portainer` |
| `--user NAME` | User to add to the `docker` group (default: the user who ran `sudo`) |
| `--dry-run` | Print every command without executing |
| `-h`, `--help` | Help |

## What it does

1. Detects the distro and architecture, refuses unsupported systems.
2. Removes conflicting packages (`docker.io`, `docker-compose` v1, `podman-docker`, ...).
3. Adds the official Docker repo with a signed key.
4. Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`.
5. Writes `/etc/docker/daemon.json` **only if absent**: log rotation (`10m x 3`) and `live-restore`.
6. Enables the service, adds the user to the `docker` group, runs `hello-world`.

The script is idempotent: if Docker and Compose are already present it exits without changes.

Compose is now a plugin: use `docker compose ...` (with a space). The legacy `docker-compose` binary is not installed.

## Portainer

```bash
sudo ./install_docker.sh -y --portainer
```

Or manually:

```bash
sudo mkdir -p /opt/portainer && cd /opt/portainer
cat > docker-compose.yml <<'YML'
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports:
      - "9443:9443"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data
volumes:
  portainer_data:
YML
docker compose up -d
```

Open `https://<server-ip>:9443` and create the admin user within 5 minutes.

**Upgrade:**

```bash
cd /opt/portainer && docker compose pull && docker compose up -d
```

> **Security:** mounting `docker.sock` grants root-equivalent access to the host. Do not expose port 9443 to the internet; restrict it with a firewall, VPN or reverse proxy with auth.

## Development

```bash
shellcheck install_docker.sh
```

CI runs ShellCheck and a dry-run on Ubuntu, Debian and CentOS Stream containers for every push (`.github/workflows/ci.yml`).

## License

[MIT](LICENSE)
