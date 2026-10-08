#!/usr/bin/env bash
# ==============================================================================
# Pop!_OS to Omarchy Linux Pre-Migration Full Backup Script
# Automatically exports packages, Docker databases, git repos, configs & credentials
# ==============================================================================
set -euo pipefail

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
BACKUP_DIR="${HOME}/omarchy-migration-backup-${TIMESTAMP}"
ARCHIVE_PATH="${HOME}/omarchy-migration-backup-${TIMESTAMP}.tar.gz"

echo "================================================================="
echo " Starting Full Machine Pre-Migration Backup"
echo " Timestamp: ${TIMESTAMP}"
echo " Destination Dir: ${BACKUP_DIR}"
echo "================================================================="

mkdir -p "${BACKUP_DIR}/"{system,docker,networking,agents,dotfiles,repos,keys}

# 1. SYSTEM PACKAGES & ENVIRONMENT
echo "[1/8] Exporting System Packages & Services..."
apt-mark showmanual > "${BACKUP_DIR}/system/apt-manual-packages.txt" 2>/dev/null || true
dpkg --get-selections > "${BACKUP_DIR}/system/dpkg-all-packages.txt" 2>/dev/null || true
flatpak list > "${BACKUP_DIR}/system/flatpak-list.txt" 2>/dev/null || true
crontab -l > "${BACKUP_DIR}/system/crontab.txt" 2>/dev/null || true
systemctl list-unit-files --state=enabled > "${BACKUP_DIR}/system/enabled-systemd-units.txt" 2>/dev/null || true
uname -a > "${BACKUP_DIR}/system/uname.txt"
cat /etc/os-release > "${BACKUP_DIR}/system/os-release.txt" 2>/dev/null || true

# Check node/npm/bun global packages if installed
if command -v npm &>/dev/null; then
    npm list -g --depth=0 > "${BACKUP_DIR}/system/npm-global-packages.txt" 2>/dev/null || true
fi
if command -v bun &>/dev/null; then
    bun pm ls -g > "${BACKUP_DIR}/system/bun-global-packages.txt" 2>/dev/null || true
fi

# 2. DOCKER CONTAINERS & DATABASES
echo "[2/8] Dumping Docker Databases & Inspecting Containers..."
docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" > "${BACKUP_DIR}/docker/docker-containers.txt" 2>/dev/null || true

# Dump Postgres containers if running
for container in sparkyfitness-db onecli-postgres-1 renerouter-postgres opnform-db; do
    if docker ps --format '{{.Names}}' | grep -Eq "^${container}\$"; then
        echo "  -> Dumping PostgreSQL container: ${container}..."
        docker exec -t "${container}" pg_dumpall -U postgres > "${BACKUP_DIR}/docker/${container}-dump.sql" 2>/dev/null || \
            echo "     [Warning] Failed to dump ${container} with pg_dumpall -U postgres"
    fi
done

# Copy docker compose files found in common project folders
mkdir -p "${BACKUP_DIR}/docker/compose-files"
find "${HOME}/Projects" "${HOME}/sparkyfitness" "${HOME}/OpnForm" "${HOME}/model-orchestrator" -maxdepth 3 \( -name "docker-compose*.yml" -o -name "compose*.yaml" -o -name "docker-compose*.yaml" \) 2>/dev/null | while read -r compose_file; do
    rel_path=$(echo "${compose_file}" | sed "s|${HOME}/||; s|/|_|g")
    cp -p "${compose_file}" "${BACKUP_DIR}/docker/compose-files/${rel_path}" 2>/dev/null || true
done

# 3. TAILSCALE & NETWORKING CONFIGS
echo "[3/8] Backing up Tailscale, Cloudflare & Network Services..."
tailscale status > "${BACKUP_DIR}/networking/tailscale-status.txt" 2>/dev/null || true
tailscale serve status > "${BACKUP_DIR}/networking/tailscale-serve-status.txt" 2>/dev/null || true

if [ -f "/home/reen/.local/bin/tailscale-dev-publish.py" ]; then
    cp -p "/home/reen/.local/bin/tailscale-dev-publish.py" "${BACKUP_DIR}/networking/tailscale-dev-publish.py"
fi

if [ -f "/etc/systemd/system/sparkyfitness-tailscale-serve.service" ]; then
    sudo cp -p "/etc/systemd/system/sparkyfitness-tailscale-serve.service" "${BACKUP_DIR}/networking/"
fi

# Tailscale state (requires sudo)
if [ -f "/var/lib/tailscale/tailscaled.state" ]; then
    echo "  -> Backing up /var/lib/tailscale/tailscaled.state (sudo required)..."
    sudo cp -p /var/lib/tailscale/tailscaled.state "${BACKUP_DIR}/networking/tailscaled.state"
    sudo chown "${USER}:${USER}" "${BACKUP_DIR}/networking/tailscaled.state"
fi

# Cloudflare configs & certs
if [ -d "${HOME}/.cloudflared" ]; then
    cp -rp "${HOME}/.cloudflared" "${BACKUP_DIR}/networking/"
fi

# 4. SSH & GPG KEYS
echo "[4/8] Backing up SSH and GPG keys..."
if [ -d "${HOME}/.ssh" ]; then
    cp -rp "${HOME}/.ssh" "${BACKUP_DIR}/keys/"
fi
if [ -d "${HOME}/.gnupg" ]; then
    cp -rp "${HOME}/.gnupg" "${BACKUP_DIR}/keys/" 2>/dev/null || true
fi

# 5. AI AGENTS & ENVIRONMENT TOKENS
echo "[5/8] Backing up AI Agents, Configurations and State..."
for dir in .claude .codex .grok .gemini .cli-proxy-api .onecli .t3 .agents; do
    if [ -d "${HOME}/${dir}" ]; then
        echo "  -> Copying ${dir}..."
        cp -rp "${HOME}/${dir}" "${BACKUP_DIR}/agents/" 2>/dev/null || true
    fi
done
for file in .claude.json claude-ping.log; do
    if [ -f "${HOME}/${file}" ]; then
        cp -p "${HOME}/${file}" "${BACKUP_DIR}/agents/" 2>/dev/null || true
    fi
done

# 6. USER DOTFILES & SHELL SETTINGS
echo "[6/8] Backing up Shell Dotfiles & ~/.config..."
for dot in .bashrc .profile .gitconfig .tmux.conf .zshrc .bash_logout .selected_editor; do
    if [ -f "${HOME}/${dot}" ]; then
        cp -p "${HOME}/${dot}" "${BACKUP_DIR}/dotfiles/"
    fi
done

# Copy ~/.config excluding huge caches
echo "  -> Backing up ~/.config (excluding browser/slack caches)..."
rsync -avq --exclude='google-chrome*' --exclude='BraveSoftware*' --exclude='Slack*' --exclude='Code/Cache*' --exclude='discord/Cache*' "${HOME}/.config/" "${BACKUP_DIR}/dotfiles/config/" 2>/dev/null || true

# 7. GIT REPOSITORIES AUDIT
echo "[7/8] Auditing Git Repositories..."
REPOS_MANIFEST="${BACKUP_DIR}/repos/git-repos-manifest.txt"
touch "${REPOS_MANIFEST}"

find "${HOME}/Projects" "${HOME}/sparkyfitness" "${HOME}/OpnForm" "${HOME}/model-orchestrator" -maxdepth 3 -name ".git" -type d 2>/dev/null | while read -r git_dir; do
    repo_dir="$(dirname "${git_dir}")"
    echo "========================================================" >> "${REPOS_MANIFEST}"
    echo "Directory: ${repo_dir}" >> "${REPOS_MANIFEST}"
    git -C "${repo_dir}" remote -v >> "${REPOS_MANIFEST}" 2>&1 || true
    echo -n "Current Branch: " >> "${REPOS_MANIFEST}"
    git -C "${repo_dir}" branch --show-current >> "${REPOS_MANIFEST}" 2>&1 || true
    echo -n "Last Commit: " >> "${REPOS_MANIFEST}"
    git -C "${repo_dir}" log -1 --oneline >> "${REPOS_MANIFEST}" 2>&1 || true
    echo "Status Summary:" >> "${REPOS_MANIFEST}"
    git -C "${repo_dir}" status -s >> "${REPOS_MANIFEST}" 2>&1 || true
done

# 8. CREATE COMPRESSED ARCHIVE & CHECKSUM
echo "[8/8] Bundling into Compressed Archive: ${ARCHIVE_PATH}..."
tar -czf "${ARCHIVE_PATH}" -C "${HOME}" "$(basename "${BACKUP_DIR}")"
SHA=$(sha256sum "${ARCHIVE_PATH}" | awk '{print $1}')
SIZE=$(du -h "${ARCHIVE_PATH}" | awk '{print $1}')

echo "================================================================="
echo " BACKUP COMPLETED SUCCESSFULLY!"
echo "================================================================="
echo " Archive Location: ${ARCHIVE_PATH}"
echo " Archive Size:     ${SIZE}"
echo " SHA256 Checksum:  ${SHA}"
echo "================================================================="
echo " NEXT CRUCIAL STEP BEFORE FORMATTING:"
echo " Transfer this archive to your Mac (mbpr) or external drive!"
echo ""
echo " Example command to copy to your Mac via Tailscale:"
echo "   scp ${ARCHIVE_PATH} rene@100.81.195.25:~/"
echo ""
echo " Also sync your project code directories to an external USB or Mac:"
echo "   rsync -avhP ~/Projects ~/sparkyfitness ~/OpnForm rene@100.81.195.25:~/pop-backup/"
echo "================================================================="
