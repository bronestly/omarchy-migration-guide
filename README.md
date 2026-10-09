# Migration Guide: Pop!_OS 24.04 to Debian 12 (Btrfs + XFCE)

> **Live Interactive Guide:** [https://bronestly.github.io/omarchy-migration-guide/](https://bronestly.github.io/omarchy-migration-guide/)

This guide details the transition from Pop!_OS 24.04 to **Debian 12 Bookworm Minimal with Btrfs root + Snapper rollback + XFCE**.

---

## Why Debian 12 Minimal for this Machine?

- **Hardware:** AMD Ryzen Embedded R1505G (2 cores / 4 threads), 5.7 GB usable RAM (shared with Radeon Vega GPU), 238 GB NVMe.
- **Resource Recovery:** Pop!_OS GNOME idles at ~1.6 GB RAM. Debian 12 + XFCE idles at **~350 MB RAM**, instantly freeing **>1.25 GB of real RAM** for your 20 Docker containers (which were thrashing in 2.6 GB swap).
- **AI-Agent Safety:** Configured with **Btrfs subvolumes + Snapper + grub-btrfs**. If an agent damages system packages or `/etc`, you can roll back with `sudo snapper rollback` or boot directly into a read-only snapshot from the GRUB menu.
- **Remote Desktop:** Native **xrdp** with XFCE works directly with Microsoft Remote Desktop on macOS / Windows with smooth clipboard sharing and auto-resizing.
- **Docker & Database Compatibility:** 1:1 package parity with Ubuntu LTS—all PostgreSQL 16 dumps, Docker Compose files, and agent credentials restore without friction.

---

## Quick Reference Commands

### 1. Pre-Migration Verification
The backup archive (`omarchy-migration-backup-LIGHT.tar.gz`, 2.3 GB) has already been sent to your Mac (`mbpr`) via Taildrop:
```bash
# On Mac (mbpr):
shasum -a 256 ~/Downloads/omarchy-migration-backup-LIGHT.tar.gz
# Expected: 14c9113ab32da01b61d659385e18d231dd2ac0a9f3051c3d2d71d5f1457f0501

# Sync project repos to Mac:
rsync -avhP --exclude 'node_modules' --exclude '.venv' ~/Projects ~/sparkyfitness ~/OpnForm rene@100.81.195.25:~/pop-full-backup/
```

### 2. Debian 12 Netinst Media
- Download: `https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso`
- Partitioning:
  - 1 GB EFI (`/boot/efi`)
  - 8 GB Swap
  - Remainder Btrfs root (`/`)
- Software selection: **Debian desktop environment**, **XFCE**, **SSH server**, **Standard system utilities**.

### 3. Post-Install Snapper Rollback Setup
```bash
sudo apt update && sudo apt install -y snapper btrfs-progs inotify-tools git
sudo snapper -c root create-config /
sudo sed -i 's/ALLOW_USERS=""/ALLOW_USERS="reen"/' /etc/snapper/configs/root
sudo systemctl enable --now snapper-timeline.timer snapper-cleanup.timer

# Enable GRUB boot menu snapshots:
git clone https://github.com/Antynea/grub-btrfs.git /tmp/grub-btrfs
cd /tmp/grub-btrfs && sudo make install
sudo systemctl enable --now grub-btrfsd
```

### 4. Remote Desktop (xrdp) & Tailscale
```bash
# Install xrdp
sudo apt install -y xrdp
sudo adduser xrdp ssl-cert
echo "startxfce4" > ~/.xsession
chmod +x ~/.xsession
sudo systemctl enable --now xrdp

# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh
sudo systemctl enable --now tailscaled
sudo tailscale up --ssh --operator=reen
```

### 5. Restore Docker & PostgreSQL Databases
```bash
# Copy backup back from Mac
scp rene@100.81.195.25:~/Downloads/omarchy-migration-backup-LIGHT.tar.gz ~/
tar -xzvf ~/omarchy-migration-backup-LIGHT.tar.gz
rsync -avhP rene@100.81.195.25:~/pop-full-backup/ ~/

# Restore Databases:
# SparkyFitness
cd ~/sparkyfitness && docker compose up -d
docker exec -i sparkyfitness-db psql -U sparky -d sparkyfitness_db < ~/omarchy-migration-backup-*/docker/sparkyfitness-db-dump.sql

# ReneRouter (CLIProxyAPI)
cd ~/Projects/renerouter && docker compose up -d
docker exec -i renerouter-postgres psql -U cliproxyapi -d cliproxyapi < ~/omarchy-migration-backup-*/docker/renerouter-postgres-dump.sql

# OneCLI
cd ~/Projects/onecli && docker compose up -d
docker exec -i onecli-postgres-1 psql -U onecli -d onecli < ~/omarchy-migration-backup-*/docker/onecli-postgres-1-dump.sql

# OpnForm
cd ~/OpnForm && docker compose up -d
docker exec -i opnform-db psql -U forge -d forge < ~/omarchy-migration-backup-*/docker/opnform-db-dump.sql
```

### 6. Restore AI Agents & Keys
```bash
cp -rp ~/omarchy-migration-backup-*/keys/.ssh ~/
chmod 700 ~/.ssh && chmod 600 ~/.ssh/*

cp -rp ~/omarchy-migration-backup-*/agents/.claude* ~/
cp -rp ~/omarchy-migration-backup-*/agents/.codex ~/
cp -rp ~/omarchy-migration-backup-*/agents/.grok ~/
cp -rp ~/omarchy-migration-backup-*/agents/.gemini ~/
cp -rp ~/omarchy-migration-backup-*/agents/.t3 ~/
cp -rp ~/omarchy-migration-backup-*/agents/.cli-proxy-api ~/
cp -rp ~/omarchy-migration-backup-*/agents/.onecli ~/
cp -rp ~/omarchy-migration-backup-*/agents/.agents ~/
```
