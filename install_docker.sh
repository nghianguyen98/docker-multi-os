#!/usr/bin/env bash
#
# install_docker.sh - Install Docker Engine + Compose v2 plugin on a fresh Linux server.
#
# Supported: Ubuntu, Debian, CentOS / Rocky / AlmaLinux / RHEL, Fedora (amd64 & arm64).
# Docs: https://github.com/nghianguyen98/docker-multi-os
#
set -Eeuo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="${0##*/}"
readonly OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
readonly OS_KERNEL="${OS_KERNEL:-$(uname -s)}"
readonly DOCKER_URL="https://download.docker.com/linux"

ASSUME_YES=0
DRY_RUN=0
INSTALL_COMPOSE=1
CONFIGURE_DAEMON=1
INSTALL_PORTAINER=0
TARGET_USER=""
SUDO=""

# ---------------------------------------------------------------- helpers
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_RST=""
fi
info() { printf '%s[INFO]%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%s[WARN]%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%s[ERROR]%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }
trap 'die "Failed at line ${LINENO}: ${BASH_COMMAND}"' ERR

usage() {
  cat <<USAGE
Usage: ${SCRIPT_NAME} [options]

Install Docker Engine, Buildx and the Compose v2 plugin from Docker's official repository.

Options:
  -y, --yes            Do not ask for confirmation
      --no-compose     Skip docker-buildx / docker-compose plugins
      --no-daemon-conf Do not write /etc/docker/daemon.json (log rotation)
      --portainer      Also deploy Portainer CE (HTTPS on :9443) in /opt/portainer
      --user NAME      Add NAME to the 'docker' group (default: the invoking user)
      --dry-run        Print the commands without executing them
  -h, --help           Show this help
USAGE
}

# run CMD...  -> execute (or just print with --dry-run)
run() {
  if (( DRY_RUN )); then
    printf '+ %s\n' "$*"
  else
    "$@"
  fi
}

# root_run CMD... -> run through sudo when not root
root_run() {
  if [[ -n "$SUDO" ]]; then run "$SUDO" "$@"; else run "$@"; fi
}

# write_root_file PATH MODE  (content on stdin)
write_root_file() {
  local path="$1" mode="$2" tmp
  tmp="$(mktemp)"
  cat >"$tmp"
  if (( DRY_RUN )); then
    printf '+ write %s (mode %s):\n' "$path" "$mode"; sed 's/^/    /' "$tmp"
  else
    root_run install -m "$mode" "$tmp" "$path"
  fi
  rm -f "$tmp"
}

confirm() {
  (( ASSUME_YES )) && return 0
  [[ -t 0 ]] || die "Non-interactive shell: re-run with -y to confirm."
  read -r -p "$1 [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || die "Aborted."
}

# ---------------------------------------------------------------- args
while (( $# )); do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --no-compose) INSTALL_COMPOSE=0 ;;
    --no-daemon-conf) CONFIGURE_DAEMON=0 ;;
    --portainer) INSTALL_PORTAINER=1 ;;
    --user) [[ $# -ge 2 ]] || die "--user needs a value"; TARGET_USER="$2"; shift ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; die "Unknown option: $1" ;;
  esac
  shift
done

# ---------------------------------------------------------------- preflight
[[ "$OS_KERNEL" == "Linux" ]] || die "Unsupported kernel '$OS_KERNEL'. On macOS install Docker Desktop, OrbStack or Colima."
[[ -r "$OS_RELEASE_FILE" ]] || die "Cannot read $OS_RELEASE_FILE - unknown distribution."

if (( EUID != 0 )); then
  command -v sudo >/dev/null 2>&1 || die "Run as root or install sudo."
  SUDO="sudo"
fi

# shellcheck disable=SC1090
. "$OS_RELEASE_FILE"
DISTRO_ID="${ID:-}"
DISTRO_LIKE=" ${ID_LIKE:-} "

FAMILY=""      # apt | rpm
REPO_DISTRO="" # path segment under download.docker.com/linux/
case "$DISTRO_ID" in
  ubuntu)                              FAMILY=apt; REPO_DISTRO=ubuntu ;;
  debian|raspbian)                     FAMILY=apt; REPO_DISTRO=debian ;;
  centos|rocky|almalinux|ol)           FAMILY=rpm; REPO_DISTRO=centos ;;
  rhel)                                FAMILY=rpm; REPO_DISTRO=rhel ;;
  fedora)                              FAMILY=rpm; REPO_DISTRO=fedora ;;
  *)
    if   [[ "$DISTRO_LIKE" == *" ubuntu "* ]]; then FAMILY=apt; REPO_DISTRO=ubuntu
    elif [[ "$DISTRO_LIKE" == *" debian "* ]]; then FAMILY=apt; REPO_DISTRO=debian
    elif [[ "$DISTRO_LIKE" == *" rhel "* || "$DISTRO_LIKE" == *" centos "* ]]; then FAMILY=rpm; REPO_DISTRO=centos
    else die "Unsupported distribution: ${PRETTY_NAME:-$DISTRO_ID}"
    fi ;;
esac

# Target user for the docker group
if [[ -z "$TARGET_USER" ]]; then
  TARGET_USER="${SUDO_USER:-}"
  [[ -z "$TARGET_USER" && $EUID -ne 0 ]] && TARGET_USER="$(id -un)"
fi

info "Detected: ${PRETTY_NAME:-$DISTRO_ID} (${FAMILY}, repo: ${REPO_DISTRO}, arch: $(uname -m))"

if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
  info "Docker + Compose already installed: $(docker --version) / $(docker compose version --short)"
  info "Nothing to do. Remove them first if you want a clean re-install."
  ALREADY_INSTALLED=1
else
  ALREADY_INSTALLED=0
  confirm "Install Docker Engine on this server?"
fi

# ---------------------------------------------------------------- install
PACKAGES=(docker-ce docker-ce-cli containerd.io)
(( INSTALL_COMPOSE )) && PACKAGES+=(docker-buildx-plugin docker-compose-plugin)

install_apt() {
  local codename arch
  if [[ "$REPO_DISTRO" == "ubuntu" ]]; then
    codename="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
  else
    codename="${VERSION_CODENAME:-}"
  fi
  [[ -n "$codename" ]] || die "Cannot determine release codename."
  arch="$(dpkg --print-architecture)"

  info "Removing conflicting packages (if any)"
  local old=(docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc)
  root_run env DEBIAN_FRONTEND=noninteractive apt-get remove -y "${old[@]}" || true

  info "Adding Docker apt repository"
  root_run apt-get update -y
  root_run env DEBIAN_FRONTEND=noninteractive apt-get install -y ca-certificates curl
  root_run install -m 0755 -d /etc/apt/keyrings
  root_run curl -fsSL "${DOCKER_URL}/${REPO_DISTRO}/gpg" -o /etc/apt/keyrings/docker.asc
  root_run chmod a+r /etc/apt/keyrings/docker.asc
  write_root_file /etc/apt/sources.list.d/docker.list 0644 <<EOL
deb [arch=${arch} signed-by=/etc/apt/keyrings/docker.asc] ${DOCKER_URL}/${REPO_DISTRO} ${codename} stable
EOL

  info "Installing: $(IFS=" "; echo "${PACKAGES[*]}")"
  root_run apt-get update -y
  root_run env DEBIAN_FRONTEND=noninteractive apt-get install -y "${PACKAGES[@]}"
}

install_rpm() {
  local pm="yum"
  command -v dnf >/dev/null 2>&1 && pm="dnf"

  info "Removing conflicting packages (if any)"
  local old=(docker docker-client docker-client-latest docker-common docker-latest \
             docker-latest-logrotate docker-logrotate docker-engine podman-docker runc)
  root_run "$pm" remove -y "${old[@]}" || true

  info "Adding Docker ${pm} repository"
  # curl-minimal (EL9 default) conflicts with the full curl package: only install if missing
  command -v curl >/dev/null 2>&1 || root_run "$pm" install -y curl
  root_run "$pm" install -y ca-certificates
  root_run curl -fsSL "${DOCKER_URL}/${REPO_DISTRO}/docker-ce.repo" -o /etc/yum.repos.d/docker-ce.repo

  info "Installing: $(IFS=" "; echo "${PACKAGES[*]}")"
  root_run "$pm" install -y "${PACKAGES[@]}"
}

if (( ! ALREADY_INSTALLED )); then
  "install_${FAMILY}"
fi

# ---------------------------------------------------------------- compat
# Keep the legacy `docker-compose` command working (forwards to the v2 plugin).
if (( INSTALL_COMPOSE )) && ! command -v docker-compose >/dev/null 2>&1; then
  info "Creating /usr/local/bin/docker-compose shim -> 'docker compose'"
  write_root_file /usr/local/bin/docker-compose 0755 <<'EOL'
#!/bin/sh
exec docker compose "$@"
EOL
fi

# ---------------------------------------------------------------- configure
HAS_SYSTEMD=0
[[ -d /run/systemd/system ]] && HAS_SYSTEMD=1

if (( CONFIGURE_DAEMON )) && [[ ! -e /etc/docker/daemon.json ]]; then
  info "Writing /etc/docker/daemon.json (log rotation, live-restore)"
  root_run install -m 0755 -d /etc/docker
  write_root_file /etc/docker/daemon.json 0644 <<'EOL'
{
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" },
  "live-restore": true
}
EOL
elif (( CONFIGURE_DAEMON )); then
  warn "/etc/docker/daemon.json already exists - left untouched."
fi

if (( HAS_SYSTEMD )); then
  root_run systemctl enable --now docker
  (( ALREADY_INSTALLED )) || root_run systemctl restart docker
else
  warn "systemd not detected (container/WSL?) - skipping service enable/start."
fi

if [[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]]; then
  if id "$TARGET_USER" >/dev/null 2>&1; then
    info "Adding '${TARGET_USER}' to the docker group"
    root_run usermod -aG docker "$TARGET_USER"
  else
    warn "User '${TARGET_USER}' does not exist - skipping docker group."
  fi
fi

# ---------------------------------------------------------------- portainer
if (( INSTALL_PORTAINER )); then
  info "Deploying Portainer CE (LTS) in /opt/portainer"
  root_run install -m 0755 -d /opt/portainer
  write_root_file /opt/portainer/docker-compose.yml 0644 <<'EOL'
services:
  portainer:
    image: portainer/portainer-ce:lts
    container_name: portainer
    restart: always
    ports:
      - "9443:9443"
      # - "8000:8000"   # only needed for Edge Agent
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - portainer_data:/data

volumes:
  portainer_data:
EOL
  root_run docker compose -f /opt/portainer/docker-compose.yml up -d
  info "Portainer: https://<server-ip>:9443 (create the admin user within 5 minutes). Restrict this port with a firewall."
fi

# ---------------------------------------------------------------- verify
if (( DRY_RUN )); then
  info "Dry run finished - nothing was changed."
  exit 0
fi

DOCKER=(docker)
[[ -n "$SUDO" ]] && DOCKER=("$SUDO" docker)

if (( HAS_SYSTEMD )); then
  info "$("${DOCKER[@]}" --version)"
  if (( INSTALL_COMPOSE )); then info "$("${DOCKER[@]}" compose version)"; fi
  "${DOCKER[@]}" run --rm hello-world >/dev/null && info "hello-world test passed."
else
  info "$(docker --version) (daemon not started - no systemd)"
fi

[[ -n "$TARGET_USER" && "$TARGET_USER" != "root" ]] && \
  warn "Log out and back in (or run 'newgrp docker') so '${TARGET_USER}' can use docker without sudo."
info "Done."
