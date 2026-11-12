# MovieNook

MovieNook is a self-hosted movie and TV setup for requesting, downloading, organizing, and watching media. It runs Plex, Seerr, Radarr, Sonarr, Prowlarr, qBittorrent, and SABnzbd with Docker Compose.

After setup, one launcher starts everything and opens **Plex**, where you do everything:

- **Add** a movie or series by putting it on your Plex Watchlist; it is requested and downloaded for you.
- **Watch** it in your Plex library.
- **Delete** it in Plex, and it is removed everywhere.

Seerr handles the requests in the background and stays available at `http://127.0.0.1:45055` if you want its extra ways to browse.

## Choose your operating system

Follow only the guide for your computer:

- [macOS setup](#macos-setup)
- [Windows setup](#windows-setup)
- [Linux setup](#linux-setup-ubuntu-or-debian)

## Before you begin

You need:

- A free Plex account.
- A Usenet provider account.
- At least one Newznab-compatible indexer account and API key.
- A VPN account if you want to use torrents through qBittorrent.

Plex cannot provide the Usenet, indexer, or VPN credentials because those are separate services. MovieNook never stores your Plex, Google, Apple, or VPN password.

# macOS setup

Complete these steps in order. Commands go in the **Terminal** application.

## macOS 1 — Install Docker and Git

macOS already includes `curl` and the `open` command.

Install Homebrew if `brew --version` says the command was not found:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Make Homebrew available in the current Terminal window:

```bash
if [[ -x /opt/homebrew/bin/brew ]]; then eval "$(/opt/homebrew/bin/brew shellenv)"; elif [[ -x /usr/local/bin/brew ]]; then eval "$(/usr/local/bin/brew shellenv)"; fi
```

Install Docker Desktop and Git, then open Docker:

```bash
brew install --cask docker
brew install git
open -a Docker
```

Accept Docker Desktop's first-run prompts. Wait until Docker reports that its engine is running, then verify the installation:

```bash
docker version
docker compose version
git --version
curl --version
```

If Homebrew cannot be used, follow Docker's official [macOS installation guide](https://docs.docker.com/desktop/setup/install/mac-install/) and install Git from [git-scm.com](https://git-scm.com/download/mac).

## macOS 2 — Download MovieNook

This places the entire project in `~/MovieNook`:

```bash
cd "$HOME"
git clone https://github.com/leopqrz/MovieNook.git MovieNook
cd MovieNook
chmod +x MovieNook.sh scripts/portable/*.sh
```

If `~/MovieNook` already exists, do not clone over it. Enter the existing folder instead:

```bash
cd "$HOME/MovieNook"
```

## macOS 3 — Create and fill the private credential file

Create the local folders and private credential file:

```bash
./scripts/portable/bootstrap.sh
```

Open the private file in TextEdit:

```bash
open -a TextEdit private/credentials.env
```

Fill in at least these fields with credentials from your own provider and indexer accounts:

```dotenv
USENET_PROVIDER_NAME=
USENET_HOST=
USENET_PORT=563
USENET_USE_SSL=true
USENET_USERNAME=
USENET_PASSWORD=

INDEXER_1_NAME=
INDEXER_1_URL=
INDEXER_1_API_KEY=
```

Save and close the file. Leave Radarr, Sonarr, Prowlarr, Seerr, SABnzbd, and qBittorrent API fields blank; MovieNook fills those local values after startup.

## macOS 4 — Start MovieNook

Double-click **MovieNook.app** in the MovieNook folder, or run:

```bash
open MovieNook.app
```

Follow the [first-launch steps](#what-happens-on-the-first-launch) when the browser opens.

## macOS daily commands

Open MovieNook:

```bash
cd "$HOME/MovieNook"
open MovieNook.app
```

Show status:

```bash
cd "$HOME/MovieNook"
./scripts/portable/status-movienook.sh
```

Stop only MovieNook services:

```bash
cd "$HOME/MovieNook"
./scripts/portable/stop-movienook.sh
```

Update and restart:

```bash
cd "$HOME/MovieNook"
git pull --ff-only
docker compose --env-file .env pull
open MovieNook.app
```

Show the latest startup errors:

```bash
cd "$HOME/MovieNook"
tail -n 100 private/last-start.log
```

# Windows setup

Complete these steps in order. Installation commands go in **PowerShell as Administrator**. MovieNook setup commands go in **Git Bash**.

## Windows 1 — Install WSL, Docker, and Git

Open PowerShell as Administrator and run:

```powershell
wsl --install
winget install --exact --id Docker.DockerDesktop
winget install --exact --id Git.Git
```

Restart Windows if `wsl --install` requests it. Open Docker Desktop from the Start menu, accept its first-run prompts, and wait until its engine is running.

Open a new PowerShell window and verify the installation:

```powershell
docker version
docker compose version
git --version
curl.exe --version
```

If `winget` is unavailable, follow Docker's official [Windows installation guide](https://docs.docker.com/desktop/setup/install/windows-install/) and install [Git for Windows](https://git-scm.com/download/win). MovieNook uses Linux containers through Docker Desktop's WSL 2 backend.

## Windows 2 — Download MovieNook

Open **Git Bash** from the Start menu and run:

```bash
cd ~
git clone https://github.com/leopqrz/MovieNook.git MovieNook
cd MovieNook
```

If the `MovieNook` folder already exists, do not clone over it. Enter the existing folder instead:

```bash
cd ~/MovieNook
```

## Windows 3 — Create and fill the private credential file

Continue in Git Bash:

```bash
./scripts/portable/bootstrap.sh
notepad.exe private/credentials.env
```

Fill in at least these fields with credentials from your own provider and indexer accounts:

```dotenv
USENET_PROVIDER_NAME=
USENET_HOST=
USENET_PORT=563
USENET_USE_SSL=true
USENET_USERNAME=
USENET_PASSWORD=

INDEXER_1_NAME=
INDEXER_1_URL=
INDEXER_1_API_KEY=
```

Save and close Notepad. Leave Radarr, Sonarr, Prowlarr, Seerr, SABnzbd, and qBittorrent API fields blank; MovieNook fills those local values after startup.

## Windows 4 — Start MovieNook

Open the `MovieNook` folder in File Explorer and double-click **MovieNook.cmd**.

From PowerShell, the equivalent command is:

```powershell
Set-Location "$HOME\MovieNook"
.\MovieNook.cmd
```

Follow the [first-launch steps](#what-happens-on-the-first-launch) when the browser opens.

## Windows daily commands

To start MovieNook, double-click **MovieNook.cmd**. From PowerShell:

```powershell
Set-Location "$HOME\MovieNook"
.\MovieNook.cmd
```

For status, stop, and update commands, open Git Bash.

Show status:

```bash
cd ~/MovieNook
./scripts/portable/status-movienook.sh
```

Stop only MovieNook services:

```bash
cd ~/MovieNook
./scripts/portable/stop-movienook.sh
```

Update and restart:

```bash
cd ~/MovieNook
git pull --ff-only
docker compose --env-file .env pull
./MovieNook.sh
```

Show the latest startup errors from PowerShell:

```powershell
Set-Location "$HOME\MovieNook"
Get-Content private\last-start.log -Tail 100
```

# Linux setup (Ubuntu or Debian)

Complete these steps in order in a terminal.

## Linux 1 — Install Docker, Compose, Git, curl, and xdg-open

These commands add Docker's official repository and install every required package:

```bash
sudo apt-get update
sudo apt-get install -y ca-certificates curl git xdg-utils nano
sudo install -m 0755 -d /etc/apt/keyrings
. /etc/os-release
sudo curl -fsSL "https://download.docker.com/linux/$ID/gpg" -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/$ID ${UBUNTU_CODENAME:-$VERSION_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list >/dev/null
sudo apt-get update
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

Log out and back in so the Docker group change takes effect. Then verify the installation without `sudo`:

```bash
docker version
docker compose version
git --version
curl --version
xdg-open --version
```

For another Linux distribution, use its official [Docker Engine installation guide](https://docs.docker.com/engine/install/) and install `git`, `curl`, and `xdg-utils` with that distribution's package manager.

## Linux 2 — Download MovieNook

This places the entire project in `~/MovieNook`:

```bash
cd "$HOME"
git clone https://github.com/leopqrz/MovieNook.git MovieNook
cd MovieNook
chmod +x MovieNook.sh scripts/portable/*.sh
```

If `~/MovieNook` already exists, do not clone over it. Enter the existing folder instead:

```bash
cd "$HOME/MovieNook"
```

## Linux 3 — Create and fill the private credential file

Create the local folders and private credential file:

```bash
./scripts/portable/bootstrap.sh
nano private/credentials.env
```

Fill in at least these fields with credentials from your own provider and indexer accounts:

```dotenv
USENET_PROVIDER_NAME=
USENET_HOST=
USENET_PORT=563
USENET_USE_SSL=true
USENET_USERNAME=
USENET_PASSWORD=

INDEXER_1_NAME=
INDEXER_1_URL=
INDEXER_1_API_KEY=
```

In Nano, save with **Ctrl+O**, press **Enter**, and exit with **Ctrl+X**. Leave Radarr, Sonarr, Prowlarr, Seerr, SABnzbd, and qBittorrent API fields blank; MovieNook fills those local values after startup.

## Linux 4 — Start MovieNook

Run:

```bash
./MovieNook.sh
```

Some Linux file managers can also run `MovieNook.sh` by double-clicking it after **Allow executing file as program** is enabled.

Follow the [first-launch steps](#what-happens-on-the-first-launch) when the browser opens.

## Linux daily commands

Start MovieNook:

```bash
cd "$HOME/MovieNook"
./MovieNook.sh
```

Show status:

```bash
cd "$HOME/MovieNook"
./scripts/portable/status-movienook.sh
```

Stop only MovieNook services:

```bash
cd "$HOME/MovieNook"
./scripts/portable/stop-movienook.sh
```

Update and restart:

```bash
cd "$HOME/MovieNook"
git pull --ff-only
docker compose --env-file .env pull
./MovieNook.sh
```

Show the latest startup errors:

```bash
cd "$HOME/MovieNook"
tail -n 100 private/last-start.log
```

# What happens on the first launch

The process is the same on every operating system:

1. **VPN check:** connect a supported full-tunnel VPN or choose to continue without one. Without a verified VPN, MovieNook starts the non-torrent services and keeps qBittorrent stopped.
2. **Plex authorization:** sign in on Plex's secure page with the new owner's Plex account and approve MovieNook. MovieNook receives an API authorization; it never receives or stores the Plex password.
3. **Automatic configuration:** MovieNook names the Plex server, creates missing Movies and TV libraries, configures Radarr and Sonarr folders, connects Prowlarr and the download clients, and connects Seerr to Plex, Radarr, and Sonarr.
4. **Plex opens:** the launcher opens your Plex library. Seerr is not opened; it works in the background.
5. **Daily use:** add titles to your Plex Watchlist to request them, and watch them in Plex.
6. **Optional Seerr sign-in:** to use Seerr's own page, open `http://127.0.0.1:45055` and click **Login with Plex** once in each new browser profile. Plex normally reuses that browser's session, and Seerr stores its own session cookie. Browser security prevents MovieNook from silently copying the Plex cookie.

Payments, invitations, CAPTCHAs, email approvals, and account sign-ins must be completed by the account owner.

# Adding a movie or show from inside Plex

You do not have to open Seerr to request something. In Plex, search for a title or browse **Discover**, then choose **Add to Watchlist**. Seerr checks the owner's Plex Watchlist every few minutes, requests anything new, and the title appears in your Plex library when the download finishes.

Everything already on the watchlist is requested the first time this runs, so remove titles you do not want downloaded. Seerr's own page still works for requests and has more ways to browse (genre, studio, upcoming).

# Deleting a movie or show

Delete it once, in either place, and MovieNook removes it everywhere:

- **In Plex:** hover the poster, open the **⋮** menu, choose **Delete**, and confirm.
- **In your file manager:** move the title's folder inside `media/Movies` or `media/TV` to the Trash.

Within about five minutes the `movienook-janitor` service removes the title from Radarr or Sonarr, so it is not downloaded again, and clears it from Seerr, so it can be requested again later. Deleting single episodes keeps the show and stops those episodes from being downloaded again; the show itself is removed once all of its episodes are gone.

The janitor never deletes a media file itself, and it ignores deletions made before it was first started. To see what it did:

```bash
docker logs movienook-janitor
```

# How automatic quality selection works

MovieNook creates a **Best Available (Auto Upgrade)** profile from the qualities exposed by Radarr and Sonarr. It discovers the available resolution ladder instead of assuming fixed quality IDs.

If only a lower-quality release is available, Radarr or Sonarr can download it first. They continue evaluating new indexer releases through their normal RSS/feed sync and replace the file when a preferred release reaches the profile cutoff. They do not repeatedly search the entire historical catalog; use a manual search if a higher-quality release already existed but was previously missed or rejected.

Prowlarr's indexers report release availability. The Usenet provider transfers the selected download but does not publish the searchable release catalog.

# VPN behavior

VPN detection works on macOS, Windows, and Linux and is not hardcoded to one provider. Tailscale is excluded because it is not a public internet privacy tunnel by itself. **Connect Another VPN Manually** supports providers MovieNook does not recognize by name.

When torrents are enabled, MovieNook starts qBittorrent only after comparing the container's public address with the VPN-routed host address. MovieNook cannot determine whether an arbitrary VPN account permits P2P.

If the VPN disconnects after startup, qBittorrent is not automatically killed. Enable the VPN client's kill switch if that guarantee is required. VPN OAuth sessions remain in the operating system's secure credential storage.

# General troubleshooting

Run these commands from the MovieNook folder.

Confirm Docker is running and show the containers:

```bash
docker info
docker compose --env-file .env ps
```

Show recent service logs:

```bash
docker compose --env-file .env logs --tail 100
```

List the configured local ports on macOS, Linux, or Git Bash:

```bash
grep '_PORT=' .env
```

List the configured ports in Windows PowerShell:

```powershell
Select-String '_PORT=' .env
```

# Keep private data out of GitHub

`private/credentials.env` is the local inventory for provider credentials, indexer credentials, local API keys, and the qBittorrent and SABnzbd Web UI credentials. It is excluded from Git.

Never publish or share:

- `.env`
- `private/`
- `config/`
- `media/`
- `downloads/`

Before committing changes, verify that Git still ignores them:

```bash
git status --short
git check-ignore .env private/credentials.env config media downloads
```

Each installation creates its own private files. Never copy one owner's populated credentials, service configuration, media library, or download history into the public repository.
