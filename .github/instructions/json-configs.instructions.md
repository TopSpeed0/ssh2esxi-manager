---
applyTo: "Configs/*.json"
description: "JSON configuration file conventions for SSH2ESXi Manager. Use when editing Commands.json or Settings.json."
---

# JSON Config Conventions

## Commands.json
- Each command set must have: `name` (string), `type` ("list" or "fix"), `description` (string), `commands` (string array)
- `type: "list"` = read-only diagnostic commands (safe to run anytime)
- `type: "fix"` = commands that modify host settings (require confirmation in GUI)
- Commands are ESXi shell commands — use `esxcli`, `grep`, `cat`, `tail`, etc.
- Always start command sets with `hostname` so output can be correlated to hosts

## Settings.json
- This file is gitignored — never reference real server names or IPs in committed code
- `vCenters` array: each entry has `name` (display label) and `server` (FQDN)
- `credentials` array: each entry has `name` (label), `user`, `encryptedPassword` (AES encrypted), `key` (Base64 AES key)
- Always use `ConvertTo-Json -Depth 10` when saving to preserve nested structure
- Always use `-Encoding UTF8` when writing JSON files
