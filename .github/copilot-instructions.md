# SSH2ESXi Manager - Copilot Instructions

## Project Overview
This is a PowerShell WPF GUI tool for managing SSH command execution on VMware ESXi hosts in parallel.
It connects to vCenter servers, discovers clusters and hosts, and runs SSH commands via Posh-SSH module.

## Architecture
- `Invoke-SSH-GUI.ps1` — Main script with WPF GUI (dark theme). Handles vCenter connection, credential management, cluster selection, command set selection, and parallel SSH execution via `Start-Job`.
- `Configs/Commands.json` — Stores SSH command sets. Each set has: `name`, `type` (list or fix), `description`, `commands` array.
- `Configs/Settings.json` — Local-only (gitignored). Stores vCenter servers and AES-256 encrypted credentials.
- `Configs/Settings.json.example` — Template for Settings.json with no real data.

## Key Patterns

### Command Sets (Commands.json)
- `type: "list"` — Read-only diagnostic commands (safe). Example: `hostname`, `esxcli network nic list`.
- `type: "fix"` — Commands that modify ESXi host settings (dangerous). Require user confirmation before execution. Example: `esxcli system settings advanced set ...`.
- New command sets are added via the GUI and saved to Commands.json.

### Credentials (Settings.json)
- Passwords are encrypted with AES-256 using a unique random key per credential entry.
- The encryption key is stored alongside the encrypted password in Settings.json (local-only file).
- vCenter credentials are for `Connect-VIServer`. ESXi SSH credentials (root) are entered per session and never saved.

### SSH Execution
- Uses `Start-Job` for parallel execution across hosts.
- Each job imports `Posh-SSH` independently (required because jobs run in separate processes).
- Before connecting, checks if `TSM-SSH` service is running on each host; skips hosts without SSH.
- Uses `New-SSHSession` with `-AcceptKey -Force` to handle host key verification.

### GUI (WPF)
- Dark theme (#1E1E1E background, VS Code style).
- All UI is defined in XAML within the script.
- Sub-windows (Add vCenter, Add Credentials, Add Command Set) are modal dialogs with `Owner = $window`.
- Uses `[System.Windows.Forms.Application]::DoEvents()` for UI refresh during long operations.

## Dependencies
- PowerShell 7+
- VMware.PowerCLI module (VMware.VimAutomation.Core)
- Posh-SSH module

## Security Rules
- NEVER commit Settings.json — it contains encrypted credentials and real server addresses.
- NEVER hardcode passwords, server names, or IP addresses in scripts.
- ESXi SSH passwords should never be saved to disk.
- Fix commands must always require user confirmation.

## Code Style
- PowerShell 7 syntax.
- Use `[PSCustomObject]@{}` for structured data.
- Use `ConvertTo-Json -Depth 10` when saving JSON.
- Use `UTF8` encoding for all file writes.
- Variable naming: `$camelCase` for local, `$script:camelCase` for script-scope.
