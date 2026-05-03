---
description: "Add a new SSH command set to Commands.json"
---

# Add Command Set

Add a new command set to `Configs/Commands.json`.

## Input
- **Name**: ${input:name:Command set display name}
- **Type**: ${input:type:list or fix}
- **Description**: ${input:description:What this command set does}
- **Commands**: ${input:commands:ESXi shell commands, one per line}

## Instructions
1. Read the current `Configs/Commands.json`
2. Add a new entry to the `commandSets` array with the provided name, type, description, and commands
3. If type is "fix", remind the user that these commands modify host settings
4. Save with `ConvertTo-Json -Depth 10`
5. Start the commands array with "hostname" if not already included
