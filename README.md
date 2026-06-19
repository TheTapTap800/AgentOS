# AgentOS

A custom **Ubuntu-based (24.04 "noble") Linux distribution** purpose-built to run
local-first AI agents. It boots straight into a fullscreen web dashboard (kiosk),
ships **OpenClaw** and **Nous Research Hermes Agent** out of the box, runs models
locally via **Ollama** with cloud-API fallback (hybrid inference), and is fully
re-configurable from another machine over SSH.

```
 install ISO on a PC  ──►  boots into pretty kiosk dashboard
        ▲                              │
        │ build in WSL2                │ manage remotely
        │                              ▼
   build/build-iso.sh        provision/ansible/deploy.yml  (from your laptop)
```

## What's inside

| Layer            | Choice                          | Why |
|------------------|---------------------------------|-----|
| Base OS          | Ubuntu 24.04 via `live-build`   | "Ubuntu remaster", broad x86_64 hardware support |
| Inference        | Ollama (local) + cloud fallback | Hybrid — cheap/offline local, heavy tasks to cloud |
| Agents           | OpenClaw + Hermes Agent         | Both installed and run as systemd services |
| Interface        | cage + Chromium kiosk → dashboard | Appliance feel, no desktop to manage |
| Remote mgmt      | Ansible over SSH                | Edit config on your laptop, deploy to the box |

## Repo layout

```
system/scripts/     install-*.sh + provision-all.sh  (single source of truth)
system/units/       systemd units for each service
dashboard/backend/  FastAPI control API (loopback only)
dashboard/frontend/ the "pretty interface" (static, glassy dark UI)
kiosk/              cage + chromium fullscreen session
build/              live-build ISO builder (run in WSL2)
provision/ansible/  remote deploy / reconfigure from your laptop
```

The same `system/scripts/provision-all.sh` runs **both** inside the ISO build
chroot and on a live machine via Ansible — so an installed box and a remotely
provisioned box are byte-for-byte the same setup.

---

## Path A — provision a plain Ubuntu install (fastest, recommended first)

No ISO needed. Install stock Ubuntu Server 24.04 on the target PC, then from your
laptop:

```bash
# 1. one-time: install Ansible on your laptop (in WSL2 or any Linux/macOS)
pip install ansible
ansible-galaxy collection install ansible.posix

# 2. point inventory at the box, copy your SSH key
ssh-copy-id agent@192.168.1.50
$EDITOR provision/ansible/inventory.ini

# 3. (optional) add API keys for the cloud half of hybrid inference
cp provision/ansible/secrets.example.env provision/ansible/secrets.env
$EDITOR provision/ansible/secrets.env

# 4. deploy
cd provision/ansible
ansible-playbook deploy.yml
```

Reboot → the box comes up in the kiosk dashboard. Re-run `ansible-playbook
deploy.yml --tags config` any time you change config on your laptop.

## Path B — build the installable ISO (the "out of the box" image)

The ISO build **must run on a Linux builder as root** — use **WSL2** on your
Windows machine. It cannot run from PowerShell.

```powershell
# in PowerShell, one-time (if WSL not present):
wsl --install -d Ubuntu
```

Optional, before building — bake your laptop's SSH key + a hostname so the
imaged box is reachable on first boot:

```bash
cp ~/.ssh/id_ed25519.pub build/authorized_keys   # one key per line
echo agentbox > build/hostname                    # optional
```

Then build inside WSL2 (needs your sudo password — it's interactive, so run it
yourself; the script auto-relocates the chroot to a native dir `~/agentos-build`
because a /mnt/c chroot can't work):

```bash
cd /mnt/c/Users/theta/Desktop/coding/AI\ Agent\ os
sudo ./build/build-iso.sh
# -> build/agentos-amd64.iso  (BIOS + UEFI, x86_64)
```

Flash it:

```bash
sudo dd if=build/agentos-amd64.iso of=/dev/sdX bs=4M status=progress && sync
# (or use Rufus / balenaEtcher on Windows)
```

Boot the target PC from the USB. First boot pulls the local model
(`hermes3:8b`) and starts every service automatically.

---

## Using it

- **Dashboard**: the kiosk shows it automatically; from your laptop browse to
  `http://<box-ip>:8080` (open the port first if you want remote access — it's
  loopback-only by default for safety).
- **Start/stop agents, view models and live logs** from the dashboard.
- **Local models**: `ssh agent@box 'ollama pull <model>'` or add to inventory.
- **Cloud keys**: edit `secrets.env`, `ansible-playbook deploy.yml --tags config`.
- **One-time Hermes setup** (required): Hermes configures via an interactive
  wizard — upstream ships no headless config. On first run:
  `ssh agent@box` (or kiosk TTY Ctrl+Alt+F2) → `hermes setup` → choose
  "Custom endpoint" → `http://127.0.0.1:11434/v1`, blank key, pick a ≥64k-context
  model. Details are in `~/.hermes/AGENTOS_SETUP_HINT.txt` on the box.

## Login

Default credentials (SSH + console):

| | |
|---|---|
| **user** | `agent` |
| **password** | `agentos` |

`agent` is a sudoer; root login is disabled. The kiosk autologins as `agent`
(no password needed for the dashboard). **Change the password** any of these ways:

- **Live (simplest):** `ssh agent@<box>` → `passwd`
- **At ISO build:** `echo 'mysecret' > build/password` before `build-iso.sh`
  (applied on first boot, then shredded from the image)
- **Per-box / fleet:** `ansible-playbook deploy.yml -e agentos_password=mysecret --tags config`
- Re-provision and OTA updates **never** reset a password you've changed.

> Change the default before exposing a box to an untrusted network.

## Updates (OTA)

Every deployed box runs `agentos-update.timer` (hourly). It polls this repo's
GitHub Releases; when a newer version tag appears it downloads that tag's source
payload and re-runs the idempotent provisioner — updating agents, dashboard,
kiosk, scripts, and units in place.

**To ship an update:** bump `VERSION`, commit, then tag and push:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

GitHub Actions (`.github/workflows/build-iso.yml`) then builds the ISO and
publishes the Release. Boxes pick up the payload automatically within the hour
(force one now with `sudo /opt/agentos/system/scripts/agentos-update.sh`).

- The OTA payload updates everything under `system/`, `dashboard/`, `kiosk/`.
  It does **not** swap the base kernel/packages — that needs a fresh ISO install
  (the Release ISO is there for exactly that).
- Repo is configured per-box in `/etc/agentos/update.conf`
  (`AGENTOS_REPO="owner/name"`, empty disables OTA).

## Security notes

- Agent control API binds to `127.0.0.1` only. The dashboard's service-control
  is gated by a **scoped** sudoers rule (`/etc/sudoers.d/agentos-dashboard`) that
  permits *only* start/stop/restart of the agent units — nothing else.
- Secrets live in `/etc/agentos/secrets.env` (mode 0600), pushed at deploy time
  and **never baked into the ISO**.
- `secrets.env` is gitignored. Don't commit keys.

## Status / caveats

- `0.1.0` scaffold. Install scripts, units, dashboard, kiosk, build, and deploy
  are complete and syntax-validated, but the **ISO build has not been run
  end-to-end here** (WSL2 has no passwordless sudo, and the build needs root +
  loop devices — you run it). Expect to tune `live-build` mirror/keyring details
  on first real build — noted inline in `build/auto/config`.
- **Install commands verified against upstream docs** (Jun 2026): OpenClaw =
  `npm i -g openclaw`, daemon `openclaw gateway`, config `~/.openclaw/openclaw.json`.
  Hermes = official `install.sh`, but it is **interactive-wizard configured** with
  no documented headless serve — hence the one-time `hermes setup` step above and
  the `hermes gateway` ExecStart (override `HERMES_SERVE_CMD` if upstream changes).
- Pin versions in `install-openclaw.sh` / `install-hermes.sh` for reproducible images.
- ARM/Raspberry Pi is out of scope for this x86_64 image; the agent stack itself
  is arch-agnostic if you retarget `build/auto/config`.
