# MovieNook

MovieNook is one local Docker Compose setup for requesting, downloading, organizing, and watching movies and TV series with Plex, Seerr, Radarr, Sonarr, Prowlarr, qBittorrent, and SABnzbd.

After the first-time setup, the normal action is one click:

- macOS: double-click **MovieNook.app**.
- Windows: double-click **MovieNook.cmd**.
- Linux: double-click **MovieNook.sh** if the desktop permits executable scripts, or run `./MovieNook.sh` in a terminal.

The launcher checks the VPN, starts the existing stack, completes safe local configuration, and opens Seerr for requests plus Plex for watching. It is safe to run repeatedly.

## 1. Install the prerequisites

MovieNook needs Docker with the Compose plugin, Git, `curl`, and a command that can open browser URLs. Use the section for the target operating system.

### macOS

macOS already includes `curl` and `open`. Install Homebrew if it is not installed:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

Install Docker Desktop and Git:

```bash
brew install --cask docker
brew install git
open -a Docker
```

Accept Docker Desktop's first-run prompts, wait until it reports that the engine is running, then verify it:

```bash
docker version
docker compose version
git --version
curl --version
```

If Homebrew cannot be used, follow Docker's official [macOS installation instructions](https://docs.docker.com/desktop/setup/install/mac-install/) and install Git from [git-scm.com](https://git-scm.com/download/mac).

### Windows 10 or 11

Open **PowerShell as Administrator** and install WSL, Docker Desktop, and Git:

```powershell
wsl --install
winget install --exact --id Docker.DockerDesktop
winget install --exact --id Git.Git
```

Restart Windows if `wsl --install` requests it. Start Docker Desktop from the Start menu, accept its first-run prompts, and then verify the tools in a new PowerShell window:

```powershell
docker version
docker compose version
git --version
curl.exe --version
```

If `winget` is unavailable, use Docker's official [Windows installation instructions](https://docs.docker.com/desktop/setup/install/windows-install/) and [Git for Windows](https://git-scm.com/download/win). MovieNook uses Linux containers through Docker Desktop's WSL 2 backend.

### Ubuntu or Debian Linux

Run these commands in a terminal. They add Docker's official repository and install Docker Engine, the Compose plugin, Git, `curl`, `xdg-open`, and a text editor:

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

Log out and back in so the Docker group change takes effect. Then verify the tools without `sudo`:

```bash
docker version
docker compose version
git --version
curl --version
xdg-open --version
```

For another Linux distribution, use the matching official [Docker Engine installation guide](https://docs.docker.com/engine/install/) and install packages named `git`, `curl`, and `xdg-utils` with that distribution's package manager.

## 2. Get MovieNook

Clone the public repository and enter its folder:

```bash
git clone https://github.com/leopqrz/MovieNook.git MovieNook
cd MovieNook
```

If the project was downloaded as a ZIP, extract it and open a terminal in the extracted `MovieNook` folder instead. Do not copy another owner's `.env`, `private`, `config`, `media`, or `downloads` folders.

## 3. Create the local files

Run the bootstrap once from the MovieNook folder. It creates `.env`, `private/credentials.env`, and the empty config, download, and media directories. It does not start services or invent external account credentials.

On macOS or Linux:

```bash
chmod +x MovieNook.sh scripts/portable/*.sh
./scripts/portable/bootstrap.sh
```

On Windows, open **Git Bash** in the MovieNook folder and run:

```bash
./scripts/portable/bootstrap.sh
```

### Enter the external account details

At least one Usenet provider and one Newznab-compatible indexer are currently required for automatic first-run wiring. Enter these fields in `private/credentials.env`:

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

Open the private file with the operating system's editor:

macOS:

```bash
open -a TextEdit private/credentials.env
```

Windows PowerShell or Git Bash:

```powershell
notepad.exe private/credentials.env
```

Linux:

```bash
nano private/credentials.env
```

Save the file. Leave locally generated fields such as Radarr, Sonarr, Prowlarr, Seerr, SABnzbd, and qBittorrent API credentials blank; MovieNook populates those after the services start. Do not put Plex, Google, Apple, or VPN passwords in this file.

## 4. Start MovieNook

Start the VPN application first when torrents are enabled. Then use the operating-system launcher.

macOS, from Terminal:

```bash
open MovieNook.app
```

Windows, from PowerShell:

```powershell
.\MovieNook.cmd
```

Linux:

```bash
./MovieNook.sh
```

The graphical files can also be double-clicked. On Linux, if the file manager opens `MovieNook.sh` as text, right-click it, allow execution as a program, or use the terminal command above.

## 5. Complete the one-time account approvals

1. When prompted about a VPN, connect any supported full-tunnel VPN or explicitly continue without one. MovieNook keeps qBittorrent stopped unless it verifies the VPN-routed public address.
2. Plex opens its secure sign-in page. Sign in with the new owner's Plex account and approve MovieNook. MovieNook receives the approval through Plex's API; it does not store a Plex, Google, or Apple password.
3. MovieNook names the server MovieNook, creates missing Movies and TV libraries, registers matching Radarr and Sonarr folders, connects Seerr to Plex/Radarr/Sonarr, and opens Seerr plus Plex.
4. In each fresh browser profile, click **Login with Plex** once in Seerr. Plex normally reuses the browser's Plex session, and Seerr stores its own session cookie. Browser security prevents MovieNook from silently copying Plex's login cookie.

Payment, invitations, CAPTCHAs, email approval, Plex sign-in, and VPN sign-in must be completed by the account owner. Usenet and indexer accounts are unrelated to Plex and cannot use the Plex login.

## Everyday commands

Run all commands from the MovieNook folder.

### Start

macOS or Linux:

```bash
./MovieNook.sh
```

Windows PowerShell:

```powershell
.\MovieNook.cmd
```

### Show status

macOS or Linux:

```bash
./scripts/portable/status-movienook.sh
```

Windows PowerShell:

```powershell
& "$Env:ProgramFiles\Git\bin\bash.exe" ./scripts/portable/status-movienook.sh
```

### Stop only MovieNook services

macOS or Linux:

```bash
./scripts/portable/stop-movienook.sh
```

Windows PowerShell:

```powershell
& "$Env:ProgramFiles\Git\bin\bash.exe" ./scripts/portable/stop-movienook.sh
```

## Update the project

Back up local state before a major update. When the folder is a Git clone, update public project files without overwriting private credentials:

```bash
git pull --ff-only
docker compose --env-file .env pull
./MovieNook.sh
```

On Windows, run the first two commands in Git Bash, then double-click `MovieNook.cmd`. Never commit or replace `.env`, `private/`, `config/`, `media/`, or `downloads/`.

## Smart quality selection

MovieNook creates a **Best Available (Auto Upgrade)** profile from the qualities already exposed by Radarr and Sonarr. It discovers the local quality IDs and resolution ladder instead of assuming fixed values, downloads the best qualifying release currently reported by the configured indexers, and keeps monitoring until the highest enabled resolution becomes available. Seerr uses this profile by default, so normal requests do not need to guess between HD and Ultra-HD.

After a lower-quality file is imported, Radarr and Sonarr evaluate newly published releases during their normal RSS/feed sync and replace it when a preferred release reaches the profile cutoff. They do not repeatedly deep-search the entire historical catalog. Run a manual search if a higher release already existed but was previously missed or rejected.

Release availability comes from Prowlarr's indexers. The Usenet provider carries a selected download but does not publish the searchable release catalog.

## VPN behavior

VPN detection is provider-neutral on macOS, Linux, and Windows; Tailscale is deliberately excluded because it is not a public internet privacy tunnel by itself. If a recognized VPN client is installed, MovieNook can open it. **Connect Another VPN Manually** supports other providers.

Without a verified VPN, MovieNook starts Plex, Seerr, Radarr, Sonarr, Prowlarr, and SABnzbd but keeps qBittorrent stopped. When enabled, qBittorrent starts only after MovieNook compares its public address with the VPN-routed host address. MovieNook cannot determine whether an arbitrary VPN subscription permits P2P.

If the VPN disconnects after startup, qBittorrent is not automatically killed. Enable the VPN client's kill switch for that guarantee. MovieNook records only the provider name and authentication method in `private/credentials.env`; VPN OAuth sessions stay in the operating system's secure credential storage.

## Troubleshooting commands

Confirm that Docker works and show every MovieNook container:

```bash
docker info
docker compose --env-file .env ps
```

Show MovieNook's latest startup log.

macOS or Linux:

```bash
tail -n 100 private/last-start.log
```

Windows PowerShell:

```powershell
Get-Content private\last-start.log -Tail 100
```

Show recent Compose logs without changing anything:

```bash
docker compose --env-file .env logs --tail 100
```

Local interfaces use the ports recorded in `.env`. List them with:

```bash
grep '_PORT=' .env
```

On Windows PowerShell, use:

```powershell
Select-String '_PORT=' .env
```

## Keep private

`private/credentials.env` is the single private inventory for external account references, locally generated API keys, qBittorrent and SABnzbd Web UI credentials, Usenet provider credentials, and indexer credentials. It is readable only by the local user and excluded from Git.

Plex and Seerr deliberately have no stored password: Plex uses browser OAuth, and Seerr uses Plex sign-in. Radarr, Sonarr, and Prowlarr use local API keys. Never put a Google or Apple SSO password in `private/credentials.env`.

Never publish `.env`, `private/`, `config/`, `media/`, or `downloads/`. `.gitignore` excludes all five, but always check before committing:

```bash
git status --short
git check-ignore .env private/credentials.env config media downloads
```

Each installation must create its own private file. Do not copy one owner's populated credentials to GitHub or another user.
