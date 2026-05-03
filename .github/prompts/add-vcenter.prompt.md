---
description: "Add a new vCenter server to Settings.json"
---

# Add vCenter

Add a new vCenter server entry to `Configs/Settings.json`.

## Input
- **Name**: ${input:name:Display name for this vCenter (e.g. NYC, PROD)}
- **Server**: ${input:server:vCenter FQDN (e.g. vcenter.example.local)}

## Instructions
1. Read the current `Configs/Settings.json`
2. Add a new entry to the `vCenters` array: `{ "name": "<name>", "server": "<server>" }`
3. Save with `ConvertTo-Json -Depth 10 -Encoding UTF8`
4. Remind the user that Settings.json is gitignored and stays local
