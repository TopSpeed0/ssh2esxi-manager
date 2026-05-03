---
applyTo: "**/*.ps1"
description: "PowerShell script conventions for SSH2ESXi Manager. Use when editing or creating PowerShell scripts in this project."
---

# PowerShell Conventions

- Target PowerShell 7+ syntax
- Use `Import-Module Posh-SSH -ErrorAction Stop` inside every `Start-Job` scriptblock — jobs run in isolated processes
- Use `3>$null` to suppress SSH warning stream on `New-SSHSession`
- Always check `TSM-SSH` service before attempting SSH: `(Get-VMHostService -VMHost $esx).Where({$_.Key -eq 'TSM-SSH'}).Running`
- Use `ConvertTo-SecureString` / `PSCredential` for credential handling — never pass plaintext passwords between functions
- For WPF GUI: define XAML as here-string, use `[System.Windows.Markup.XamlReader]::Load()` to parse
- Use `[System.Windows.Forms.Application]::DoEvents()` for UI updates during synchronous operations
- Prefer `[System.Text.StringBuilder]` for building large output strings
- Use `Remove-Job -Force` after collecting results to clean up background jobs
