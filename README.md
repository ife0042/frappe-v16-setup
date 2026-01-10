## Frappe v16 Setup Scripts

These scripts automate a two-phase provisioning flow for a Frappe v16 development/test environment on Ubuntu 24.04 LTS (Noble) only. They separate privileged, system-level tasks from user-level app setup for better security and repeatability, and provide a single-command orchestrator for convenience.

### What’s included
- **`root-system-setup.sh`**: Root-only, system bootstrap.
  - Creates the Frappe system user and configures passwordless sudo (with a security note below).
  - Optionally adds an SSH public key to `root` for remote access.
  - Installs core packages: Git, Redis, MariaDB server/client, build tools, and wkhtmltopdf deps.
- **`setup-frappe-app.sh`**: Non-root, app user setup.
  - Secures MariaDB via `mariadb-secure-installation` (non-interactive).
  - Installs wkhtmltopdf for Ubuntu 24.04 (Noble), Node via NVM, Yarn, `uv` for Python, Bench CLI.
  - Initializes a bench and creates a Frappe site, optionally enabling developer mode.
- **`setup-orchestrator.sh`**: Root-only, end-to-end automation.
  - Runs the root phase, then switches to the app user and runs the user phase with your parameters.
  - Recommended for a one-shot setup.

All scripts log to `/tmp/<script-name>-YYYY-MM-DD.log` for troubleshooting.

---

## Supported environment
- **OS**: Ubuntu 24.04 LTS (Noble).
  - Reason: Scripted package versions and wkhtmltopdf build target Noble specifically.
- **Network**: Outbound internet access (downloads `nvm`, `uv`, wkhtmltopdf, Bench).
- **Privileges**: `root` is required for system setup; the app phase must run as the target non-root user.

Note: These scripts are not intended for macOS or Windows. Use a Linux VM or server.

---

## Why it’s split into two phases
- **Least privilege**: Only root does user creation, sudoers, and system packages. Everything Frappe/bench/site-related runs as a normal user.
- **Repeatability**: You can re-run the user phase without re-touching system config.
- **Security**: Avoids running the Frappe stack as root.

Security caveat: Passwordless sudo is added for the app user to streamline setup and routine operations. If this is not desired in your environment, remove or tighten the sudoers entry after installation.

---

## Installation (place scripts on the server)
```bash
sudo mkdir -p /opt/frappe-v16-setup
# Replace /path/to/local/repo with your actual path
sudo cp -a /path/to/local/repo/* /opt/frappe-v16-setup/
sudo chmod +x /opt/frappe-v16-setup/*.sh
```

You can also run them from any directory, but the orchestrator assumes the scripts live together.

---

## Quick start (recommended)
Run the full orchestration as root. This performs both phases and passes the right arguments through.

```bash
sudo /opt/frappe-v16-setup/setup-orchestrator.sh \
  -u frappe \
  -p 'mariadb_root_password' \
  -s 'apps.localhost' \
  -a 'frappe_admin_password' \
  -d true \
  -k "ssh-ed25519 AAAA... user@example.com"
```

- **-u**: Name of the system user to own the Frappe stack (e.g., `frappe`).
- **-p**: MariaDB root password to set/use.
- **-s**: Frappe site name (e.g., `apps.localhost`).
- **-a**: Frappe Administrator password.
- **-d**: Developer mode (`true` or `false`, default `false`).
- **-k**: Optional SSH public key to add to `root`’s `authorized_keys` (quote the whole key). Useful for remote access.

Reasons for key flags:
- Providing `-k` during bootstrap ensures you won’t get locked out when password auth is disabled later.
- `-d true` enables developer functionality like schema syncs and JS builds suitable for dev environments.

---

## Manual two-phase flow (advanced)

### 1) Root/system phase
Run as root to create the app user, set sudoers, and install base packages.

```bash
sudo /opt/frappe-v16-setup/root-system-setup.sh \
  -u frappe \
  -k "ssh-ed25519 AAAA... user@example.com"
```

Arguments:
- **-u/--user**: Required. App user to create and grant passwordless sudo.
- **-k/--ssh-key**: Optional. Public key to add to `root` for SSH.

What this does (and why):
- Creates user and grants NOPASSWD sudo (helps during frequent dev tasks; review in production).
- Installs Git, Redis, MariaDB server/client, build deps, and wkhtmltopdf dependencies – all required by Frappe and Bench.

Next, switch to the app user:
```bash
sudo su - frappe
```

### 2) User/app phase
Run as the target app user (not root). This secures MariaDB, installs runtime tools, initializes bench, and creates the site.

```bash
/opt/frappe-v16-setup/setup-frappe-app.sh \
  -u frappe \
  -p 'mariadb_root_password' \
  -s 'apps.localhost' \
  -a 'frappe_admin_password' \
  -d true
```

Arguments:
- **-u**: Must match the current UNIX user.
- **-p**: MariaDB root password used by `bench new-site`.
- **-s**: Site name to create.
- **-a**: Frappe Administrator password.
- **-d**: Developer mode (`true`/`false`), default `false`.

What this installs (and why):
- **MariaDB secure install**: Hardens defaults for local dev (root password, remove test DB, etc.).
 - **wkhtmltopdf (Ubuntu 24.04 build)**: Required for PDF generation in Frappe.
- **NVM + Node 24 + Yarn**: Frappe asset builds rely on Node/Yarn.
- **uv + Python 3.14**: Fast, reproducible Python toolchain management.
- **Bench CLI (5.28)**: Official tool to manage Frappe benches.
- Bench init with `--frappe-branch version-16-beta` and site creation.

---

## After setup
- Your bench lives in `~/frappe-bench` for the app user.
- To run the development server:
  ```bash
  cd ~/frappe-bench
  source env/bin/activate && bench start
  ```
- Production hardening (Supervisor, Nginx, SSL, firewall) is not included here.

---

## Logging & troubleshooting
- Each script writes to `/tmp/<script-name>-YYYY-MM-DD.log`. Check these logs first when diagnosing failures.
- The orchestrator exits on errors and reports the line number where a failure occurred.

---

## Security notes and best practices
- Avoid keeping plaintext passwords in shell history. Consider using a throwaway session or clearing history after running.
- Review and adjust the passwordless sudoers entry for the app user if you need stricter controls.
 - The script targets Ubuntu 24.04 (Noble) when fetching the wkhtmltopdf package.

---

## Reference: Script usage help

### `setup-orchestrator.sh`
```bash
sudo /opt/frappe-v16-setup/setup-orchestrator.sh \
  -u <user> -p <db_root_pw> -s <site> -a <admin_pw> [-d true|false] [-k "<ssh_pub_key>"]
```

### `root-system-setup.sh`
```bash
sudo /opt/frappe-v16-setup/root-system-setup.sh \
  -u <user> [-k "<ssh_pub_key>"]
```

### `setup-frappe-app.sh`
```bash
/opt/frappe-v16-setup/setup-frappe-app.sh \
  -u <user> -p <db_root_pw> -s <site> -a <admin_pw> [-d true|false]
```

