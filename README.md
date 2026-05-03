# SSH2ESXi Manager
<img width="886" height="793" alt="image" src="https://github.com/user-attachments/assets/31f949e9-12c4-460f-9b6b-6d488346af3d" />

A PowerShell WPF GUI tool for running SSH commands on VMware ESXi hosts in parallel across clusters.

## Overview

This tool replaces the old script-based approach (`Invoke-SSH-ParallelGeneric.ps1` + `ListCommand.ps1` + `FixCommands.ps1`) with a single GUI application that manages everything dynamically — no hardcoded values.

### What it does
- Connects to any vCenter server
- Runs SSH commands in parallel on all ESXi hosts in a selected cluster
- Manages multiple command sets (list/diagnostics and fix/remediation)
- Stores encrypted credentials locally
- Saves all output to a log file

## Architecture

```
ssh2esxi-manager/
├── Invoke-SSH-GUI.ps1          # Main GUI script (WPF)
├── Configs/
│   ├── Commands.json           # SSH command sets (list & fix)
│   ├── Settings.json           # vCenters + encrypted credentials (local, gitignored)
│   └── Settings.json.example   # Template for Settings.json
├── .gitignore
└── README.md
```

### Commands.json
Stores all SSH command sets with metadata:
```json
{
  "commandSets": [
    {
      "name": "Hostname",
      "type": "list",
      "description": "Get hostname only",
      "commands": ["hostname"]
    }
  ]
}
```
- **type: `list`** — Read-only diagnostic commands (safe to run)
- **type: `fix`** — Commands that modify host settings (requires confirmation)

New command sets can be added via the GUI and are saved to this file.

### Settings.json
Stores vCenter servers and encrypted credentials:
```json
{
  "vCenters": [
    { "name": "THC", "server": "thcpvc01.cognyte.local" }
  ],
  "credentials": [
    {
      "name": "vCenter Admin",
      "user": "administrator@vsphere.local",
      "encryptedPassword": "...",
      "key": "..."
    }
  ]
}
```
- Passwords are encrypted using AES-256 with a random key per credential
- Both vCenters and credentials can be added via the GUI
- **This file is gitignored** — each user creates their own via the GUI

## Prerequisites

- **PowerShell 7+**
- **VMware PowerCLI** — `Install-Module VMware.PowerCLI`
- **Posh-SSH** — `Install-Module Posh-SSH`

## Usage

### First Time Setup
1. Run the script:
   ```powershell
   & '.\Invoke-SSH-GUI.ps1'
   ```
2. Click **+ vCenter** to add your vCenter server(s)
3. Click **+ Credentials** to add your vCenter credentials (stored encrypted locally)
4. Select vCenter + Credentials and click **Connect**

### Running Commands
1. Connect to a vCenter (see above)
2. Select a **Cluster** from the dropdown
3. Enter **ESXi User** (default: `root`) and **ESXi Password**
4. Select a **Command Set** from the dropdown
5. Click **Run Commands**
6. Results appear in the Output panel and are saved to the log file

### Adding New Command Sets
1. Click **+ Add New Set**
2. Enter name, type (list/fix), description
3. Enter commands (one per line)
4. Click Save — saved to `Commands.json`

## GUI Layout

| Section | Description |
|---------|-------------|
| **vCenter Connection** | Select vCenter + credentials, connect, add new ones |
| **ESXi SSH Connection** | ESXi user/password, cluster selection |
| **Command Set** | Select which commands to run, preview them |
| **Run/Stop** | Execute commands (with confirmation for fix commands) |
| **Output** | Real-time results from all hosts |
| **Log file** | Path for saving output (default: `c:\temp\out.log`) |

## Included Command Sets

### List (Diagnostics)
| Name | Description |
|------|-------------|
| Hostname | Get hostname only |
| HW and Storage Info | HardwareAcceleratedInit, MaxHWTransferSize, iSCSI, SATP rules |
| IOPS Check | NetApp IOPS and SATP rules |
| CRC Errors | CRC errors on vmnic0/vmnic1 |
| iSCSI Errors | iSCSI and MTU errors in vmkwarning |
| Syslog and VMKWarning | Tail syslog and vmkwarning logs |
| PAM Auth Failures | Authentication failures in auth log |
| All Network Commands | Full NIC diagnostics — link events, CRC, path state, errors |

### Fix (Remediation)
| Name | Description |
|------|-------------|
| Fix HW/iSCSI/SATP | MaxHWTransferSize, iSCSI LunQDepth, SATP rules, digest |
| Fix NetApp SATP | NetApp SATP rule + round-robin on specific LUNs |
| NTP Settings (CYP/IL/BR) | Configure NTP per site |
| Enable VAAI | Enable all VAAI HW acceleration settings |
| Syslog Config | Configure remote syslog |

## How It Works (Technical)

1. **vCenter Connection** — Uses `Connect-VIServer` with encrypted credentials from `Settings.json`
2. **Cluster Discovery** — `Get-Cluster` lists all clusters from the connected vCenter
3. **SSH Check** — For each host, checks if `TSM-SSH` service is running; skips hosts without SSH
4. **Parallel Execution** — Uses `Start-Job` to run SSH commands in parallel across all hosts
5. **SSH via Posh-SSH** — Each job imports `Posh-SSH`, creates an SSH session, runs the command, and returns output
6. **Results** — All job outputs are collected, displayed in the GUI, and saved to the log file

## Migration from Old Scripts

| Old | New |
|-----|-----|
| `Invoke-SSH-ParallelGeneric.ps1` | `Invoke-SSH-GUI.ps1` |
| `Configs/ListCommand.ps1` | `Configs/Commands.json` (type: list) |
| `Configs/FixCommands.ps1` | `Configs/Commands.json` (type: fix) |
| `VMware connections_dev.ps1` | Built into GUI (vCenter Connection section) |
| Hardcoded passwords | Encrypted in `Settings.json` |
| Hardcoded cluster names | Selected via GUI dropdown |
| `Out-GridView` for selection | WPF GUI dropdowns |

## Security Notes

- vCenter passwords are encrypted with AES-256 (unique random key per credential)
- ESXi passwords are entered per session and never saved
- `Settings.json` is gitignored — never committed
- Fix commands require explicit confirmation before execution
