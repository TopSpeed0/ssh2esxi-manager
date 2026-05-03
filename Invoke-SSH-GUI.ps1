<#
    Invoke-SSH-GUI.ps1
    WPF GUI for running SSH commands on ESXi hosts in parallel.
    - Manages vCenter connections and credentials via Settings.json
    - Loads command sets from Commands.json, allows adding new sets.
#>

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms

Import-Module VMware.VimAutomation.Core -Force -SkipEditionCheck -ErrorAction SilentlyContinue | Out-Null

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$jsonPath = Join-Path $scriptRoot 'Configs\Commands.json'
$settingsPath = Join-Path $scriptRoot 'Configs\Settings.json'

#region Config File Initialization & Validation
$script:placeholderPattern = '<[A-Z_]+>'

function Initialize-ConfigFiles {
    $configFiles = @(
        @{ Name = 'Commands.json';  Path = $jsonPath;     ExamplePath = Join-Path $scriptRoot 'Configs\Commands.json.example' }
        @{ Name = 'Settings.json';  Path = $settingsPath;  ExamplePath = Join-Path $scriptRoot 'Configs\Settings.json.example' }
    )

    foreach ($cfg in $configFiles) {
        if (-not (Test-Path $cfg.Path)) {
            if (Test-Path $cfg.ExamplePath) {
                $result = [System.Windows.MessageBox]::Show(
                    "$($cfg.Name) does not exist.`nWould you like to create it from $($cfg.Name).example?`n`nYou will need to update placeholder values afterward.",
                    "Create $($cfg.Name)",
                    [System.Windows.MessageBoxButton]::YesNo,
                    [System.Windows.MessageBoxImage]::Question
                )
                if ($result -eq 'Yes') {
                    Copy-Item -Path $cfg.ExamplePath -Destination $cfg.Path -Force
                }
            } else {
                # No .example file either — create minimal default for Settings.json
                if ($cfg.Name -eq 'Settings.json') {
                    @{ vCenters = @(); credentials = @() } | ConvertTo-Json -Depth 10 | Set-Content $cfg.Path -Encoding UTF8
                }
            }
        }
    }
}

function Test-PlaceholdersInConfig {
    $configFiles = @(
        @{ Name = 'Commands.json'; Path = $jsonPath }
        @{ Name = 'Settings.json'; Path = $settingsPath }
    )

    $allPlaceholders = @()
    foreach ($cfg in $configFiles) {
        if (-not (Test-Path $cfg.Path)) { continue }
        $content = Get-Content $cfg.Path -Raw
        $matches = [regex]::Matches($content, $script:placeholderPattern)
        if ($matches.Count -gt 0) {
            $uniqueValues = ($matches | ForEach-Object { $_.Value } | Sort-Object -Unique) -join ', '
            $allPlaceholders += "$($cfg.Name): $uniqueValues"
        }
    }

    if ($allPlaceholders.Count -gt 0) {
        $msg = "The following config files contain placeholder values that should be updated:`n`n"
        $msg += ($allPlaceholders -join "`n")
        $msg += "`n`nWould you like to continue anyway?"
        $result = [System.Windows.MessageBox]::Show(
            $msg,
            'Placeholder Values Detected',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        return ($result -eq 'Yes')
    }
    return $true
}

function Test-ConfigMatchesExample {
    $configPairs = @(
        @{ Name = 'Commands.json'; Path = $jsonPath;     ExamplePath = Join-Path $scriptRoot 'Configs\Commands.json.example' }
        @{ Name = 'Settings.json'; Path = $settingsPath;  ExamplePath = Join-Path $scriptRoot 'Configs\Settings.json.example' }
    )

    $unchanged = @()
    foreach ($pair in $configPairs) {
        if ((Test-Path $pair.Path) -and (Test-Path $pair.ExamplePath)) {
            $configHash = (Get-FileHash -Path $pair.Path -Algorithm SHA256).Hash
            $exampleHash = (Get-FileHash -Path $pair.ExamplePath -Algorithm SHA256).Hash
            if ($configHash -eq $exampleHash) {
                $unchanged += $pair.Name
            }
        }
    }

    if ($unchanged.Count -gt 0) {
        $msg = "The following config files are identical to their .example templates:`n`n"
        $msg += ($unchanged -join "`n")
        $msg += "`n`nPlease update them with your actual values.`nWould you like to continue anyway?"
        $result = [System.Windows.MessageBox]::Show(
            $msg,
            'Config Files Not Modified',
            [System.Windows.MessageBoxButton]::YesNo,
            [System.Windows.MessageBoxImage]::Warning
        )
        return ($result -eq 'Yes')
    }
    return $true
}

# Run initialization
Initialize-ConfigFiles

# Validate configs — allow user to dismiss warnings
$continueAfterExampleCheck = Test-ConfigMatchesExample
if (-not $continueAfterExampleCheck) {
    Write-Host "User chose to exit — config files need to be updated." -ForegroundColor Yellow
    exit
}

$continueAfterPlaceholders = Test-PlaceholdersInConfig
if (-not $continueAfterPlaceholders) {
    Write-Host "User chose to exit — placeholder values need to be replaced." -ForegroundColor Yellow
    exit
}
#endregion

#region Helper Functions
function Load-Settings {
    Get-Content $settingsPath -Raw | ConvertFrom-Json
}

function Save-Settings {
    param($settings)
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
}

function Encrypt-Credential {
    param([string]$user, [string]$password)
    $key = New-Object byte[] 32
    [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($key)
    $secStr = ConvertTo-SecureString -String $password -AsPlainText -Force
    $encrypted = $secStr | ConvertFrom-SecureString -Key $key
    return @{ user = $user; encryptedPassword = $encrypted; key = [System.Convert]::ToBase64String($key) }
}

function Decrypt-Credential {
    param($credEntry)
    $keyBytes = [System.Convert]::FromBase64String($credEntry.key)
    $secStr = $credEntry.encryptedPassword | ConvertTo-SecureString -Key $keyBytes
    return New-Object System.Management.Automation.PSCredential($credEntry.user, $secStr)
}
#endregion

#region XAML
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="VMware SSH Command Runner" Height="800" Width="900"
        WindowStartupLocation="CenterScreen" Background="#1E1E1E">
    <Window.Resources>
        <Style TargetType="Label">
            <Setter Property="Foreground" Value="#CCCCCC"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="TextBox">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#CCCCCC"/>
            <Setter Property="BorderBrush" Value="#3F3F3F"/>
            <Setter Property="Padding" Value="4"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="PasswordBox">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#CCCCCC"/>
            <Setter Property="BorderBrush" Value="#3F3F3F"/>
            <Setter Property="Padding" Value="4"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="ComboBox">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#111111"/>
            <Setter Property="BorderBrush" Value="#3F3F3F"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="#0E639C"/>
            <Setter Property="Foreground" Value="White"/>
            <Setter Property="BorderBrush" Value="#0E639C"/>
            <Setter Property="Padding" Value="10,5"/>
            <Setter Property="FontSize" Value="12"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
        <Style TargetType="ListBox">
            <Setter Property="Background" Value="#2D2D2D"/>
            <Setter Property="Foreground" Value="#CCCCCC"/>
            <Setter Property="BorderBrush" Value="#3F3F3F"/>
            <Setter Property="FontSize" Value="13"/>
        </Style>
    </Window.Resources>
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>

        <!-- Row 0: vCenter Connection -->
        <GroupBox Grid.Row="0" Header="vCenter Connection" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Margin="0,0,0,8">
            <Grid Margin="5">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <Label Grid.Row="0" Grid.Column="0" Content="vCenter:" Margin="0,0,5,0"/>
                <ComboBox Grid.Row="0" Grid.Column="1" Name="cmbVCenter" Margin="0,2,10,2"/>
                <Label Grid.Row="0" Grid.Column="2" Content="Credentials:" Margin="0,0,5,0"/>
                <ComboBox Grid.Row="0" Grid.Column="3" Name="cmbCredentials" Margin="0,2,10,2"/>
                <Button Grid.Row="0" Grid.Column="4" Name="btnConnect" Content="Connect" Background="#16825D" BorderBrush="#16825D" Margin="0,2,0,2"/>
                <StackPanel Grid.Row="1" Grid.Column="0" Grid.ColumnSpan="3" Orientation="Horizontal" Margin="0,4,0,0">
                    <Button Name="btnAddVC" Content="+ vCenter" Margin="0,0,8,0" FontSize="11" Background="#3F3F3F" BorderBrush="#3F3F3F"/>
                    <Button Name="btnAddCred" Content="+ Credentials" Margin="0,0,8,0" FontSize="11" Background="#3F3F3F" BorderBrush="#3F3F3F"/>
                </StackPanel>
                <TextBlock Grid.Row="1" Grid.Column="3" Grid.ColumnSpan="2" Name="lblConnectionStatus" 
                           Foreground="#888888" FontSize="12" Margin="4,6,0,0" VerticalAlignment="Center" Text="Not connected"/>
            </Grid>
        </GroupBox>

        <!-- Row 1: ESXi SSH Settings -->
        <GroupBox Grid.Row="1" Header="ESXi SSH Connection" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Margin="0,0,0,8">
            <Grid Margin="5">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                    <ColumnDefinition Width="*"/>
                </Grid.ColumnDefinitions>
                <Label Grid.Row="0" Grid.Column="0" Content="ESXi User:" Margin="0,0,5,0"/>
                <TextBox Grid.Row="0" Grid.Column="1" Name="txtUser" Text="root" Margin="0,2,10,2"/>
                <Label Grid.Row="0" Grid.Column="2" Content="ESXi Password:" Margin="0,0,5,0"/>
                <PasswordBox Grid.Row="0" Grid.Column="3" Name="txtPassword" Margin="0,2,10,2"/>
                <Label Grid.Row="0" Grid.Column="4" Content="Cluster:" Margin="0,0,5,0"/>
                <ComboBox Grid.Row="0" Grid.Column="5" Name="cmbCluster" Margin="0,2,0,2"/>
            </Grid>
        </GroupBox>

        <!-- Row 2: Command Set Selection -->
        <GroupBox Grid.Row="2" Header="Command Set" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Margin="0,0,0,8">
            <Grid Margin="5">
                <Grid.ColumnDefinitions>
                    <ColumnDefinition Width="*"/>
                    <ColumnDefinition Width="Auto"/>
                </Grid.ColumnDefinitions>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <ComboBox Grid.Row="0" Grid.Column="0" Name="cmbCommandSet" Margin="0,2,10,2"/>
                <Button Grid.Row="0" Grid.Column="1" Name="btnAddSet" Content="+ Add New Set" Margin="0,2,0,2"/>
                <TextBlock Grid.Row="1" Grid.Column="0" Name="lblDescription" Foreground="#888888" FontSize="12" Margin="4,2,0,4" TextWrapping="Wrap"/>
            </Grid>
        </GroupBox>

        <!-- Row 3: Commands Preview -->
        <GroupBox Grid.Row="3" Header="Commands Preview" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Margin="0,0,0,8">
            <ListBox Name="lstCommands" Height="100" Margin="5" SelectionMode="Single"/>
        </GroupBox>

        <!-- Row 4: Run -->
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Center" Margin="0,0,0,8">
            <Button Name="btnRun" Content="Run Commands" Width="150" Margin="0,0,10,0" FontSize="14" FontWeight="Bold"/>
            <Button Name="btnStop" Content="Stop" Width="80" Background="#C42B1C" BorderBrush="#C42B1C" IsEnabled="False"/>
        </StackPanel>

        <!-- Row 5: Status -->
        <Label Grid.Row="5" Name="lblStatus" Content="Ready" Foreground="#569CD6" FontSize="12"/>

        <!-- Row 6: Output -->
        <GroupBox Grid.Row="6" Header="Output" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Margin="0,0,0,8">
            <TextBox Name="txtOutput" IsReadOnly="True" VerticalScrollBarVisibility="Auto"
                     HorizontalScrollBarVisibility="Auto" TextWrapping="Wrap"
                     FontFamily="Consolas" FontSize="12" AcceptsReturn="True"
                     Background="#1A1A1A" Foreground="#D4D4D4"/>
        </GroupBox>

        <!-- Row 7: Log path -->
        <StackPanel Grid.Row="7" Orientation="Horizontal">
            <Label Content="Log file:" FontSize="11"/>
            <TextBox Name="txtLogPath" Text="c:\temp\out.log" Width="300" FontSize="11" Margin="0,2,0,0"/>
        </StackPanel>
    </Grid>
</Window>
"@
#endregion

#region Load Window
$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [System.Windows.Markup.XamlReader]::Load($reader)

$cmbVCenter    = $window.FindName('cmbVCenter')
$cmbCredentials = $window.FindName('cmbCredentials')
$btnConnect    = $window.FindName('btnConnect')
$btnAddVC      = $window.FindName('btnAddVC')
$btnAddCred    = $window.FindName('btnAddCred')
$lblConnectionStatus = $window.FindName('lblConnectionStatus')
$txtUser       = $window.FindName('txtUser')
$txtPassword   = $window.FindName('txtPassword')
$cmbCluster    = $window.FindName('cmbCluster')
$cmbCommandSet = $window.FindName('cmbCommandSet')
$lblDescription = $window.FindName('lblDescription')
$lstCommands   = $window.FindName('lstCommands')
$btnRun        = $window.FindName('btnRun')
$btnStop       = $window.FindName('btnStop')
$btnAddSet     = $window.FindName('btnAddSet')
$lblStatus     = $window.FindName('lblStatus')
$txtOutput     = $window.FindName('txtOutput')
$txtLogPath    = $window.FindName('txtLogPath')
#endregion

#region Load Data
function Load-CommandSets {
    $json = Get-Content $jsonPath -Raw | ConvertFrom-Json
    return $json.commandSets
}

function Save-CommandSets {
    param($commandSets)
    $json = [PSCustomObject]@{ commandSets = $commandSets }
    $json | ConvertTo-Json -Depth 10 | Set-Content $jsonPath -Encoding UTF8
}

function Refresh-VCenterList {
    $cmbVCenter.Items.Clear()
    $settings = Load-Settings
    foreach ($vc in $settings.vCenters) {
        $cmbVCenter.Items.Add("$($vc.name) ($($vc.server))") | Out-Null
    }
    if ($cmbVCenter.Items.Count -gt 0) { $cmbVCenter.SelectedIndex = 0 }
}

function Refresh-CredentialsList {
    $cmbCredentials.Items.Clear()
    $settings = Load-Settings
    foreach ($c in $settings.credentials) {
        $cmbCredentials.Items.Add($c.name) | Out-Null
    }
    if ($cmbCredentials.Items.Count -gt 0) { $cmbCredentials.SelectedIndex = 0 }
}

function Refresh-ClusterList {
    $cmbCluster.Items.Clear()
    try {
        $clusters = Get-Cluster -ErrorAction Stop | Select-Object -ExpandProperty Name | Sort-Object
        foreach ($c in $clusters) { $cmbCluster.Items.Add($c) | Out-Null }
        if ($cmbCluster.Items.Count -gt 0) { $cmbCluster.SelectedIndex = 0 }
    } catch {}
}

# Initial load
Refresh-VCenterList
Refresh-CredentialsList
Refresh-ClusterList

# Check if already connected
if ($global:DefaultVIServers.Count -gt 0) {
    $lblConnectionStatus.Text = "Connected: $($global:DefaultVIServers.Name -join ', ')"
    $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen
}

# Load command sets
$script:commandSets = Load-CommandSets
foreach ($cs in $script:commandSets) {
    $prefix = if ($cs.type -eq 'fix') { '[FIX] ' } else { '[LIST] ' }
    $cmbCommandSet.Items.Add("$prefix$($cs.name)") | Out-Null
}
if ($cmbCommandSet.Items.Count -gt 0) { $cmbCommandSet.SelectedIndex = 0 }
#endregion

#region vCenter Events

# Add vCenter
$btnAddVC.Add_Click({
    $addXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add vCenter" Height="200" Width="450"
        WindowStartupLocation="CenterOwner" Background="#1E1E1E" ResizeMode="NoResize">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Name:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtVCName" Width="300" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,12">
            <Label Content="Server:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtVCServer" Width="300" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnSaveVC" Content="Save" Width="80" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderBrush="#0E639C" Padding="8,4"/>
            <Button Name="btnCancelVC" Content="Cancel" Width="80" Background="#3F3F3F" Foreground="White" BorderBrush="#3F3F3F" Padding="8,4"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $r = New-Object System.Xml.XmlNodeReader ([xml]$addXaml)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    $w.Owner = $window
    $w.FindName('btnCancelVC').Add_Click({ $w.Close() })
    $w.FindName('btnSaveVC').Add_Click({
        $name = $w.FindName('txtVCName').Text.Trim()
        $server = $w.FindName('txtVCServer').Text.Trim()
        if (-not $name -or -not $server) {
            [System.Windows.MessageBox]::Show("Name and Server are required.", "Error", "OK", "Error"); return
        }
        $settings = Load-Settings
        $settings.vCenters += [PSCustomObject]@{ name = $name; server = $server }
        Save-Settings $settings
        Refresh-VCenterList
        $cmbVCenter.SelectedIndex = $cmbVCenter.Items.Count - 1
        $w.Close()
    })
    $w.ShowDialog() | Out-Null
})

# Add Credentials
$btnAddCred.Add_Click({
    $addXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add Credentials" Height="250" Width="450"
        WindowStartupLocation="CenterOwner" Background="#1E1E1E" ResizeMode="NoResize">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Label:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtCredName" Width="300" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Username:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtCredUser" Width="300" Text="administrator@vsphere.local" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,12">
            <Label Content="Password:" Foreground="#CCCCCC" Width="80"/>
            <PasswordBox Name="txtCredPass" Width="300" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnSaveCred" Content="Save (Encrypted)" Width="130" Margin="0,0,10,0" Background="#0E639C" Foreground="White" BorderBrush="#0E639C" Padding="8,4"/>
            <Button Name="btnCancelCred" Content="Cancel" Width="80" Background="#3F3F3F" Foreground="White" BorderBrush="#3F3F3F" Padding="8,4"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $r = New-Object System.Xml.XmlNodeReader ([xml]$addXaml)
    $w = [System.Windows.Markup.XamlReader]::Load($r)
    $w.Owner = $window
    $w.FindName('btnCancelCred').Add_Click({ $w.Close() })
    $w.FindName('btnSaveCred').Add_Click({
        $name = $w.FindName('txtCredName').Text.Trim()
        $user = $w.FindName('txtCredUser').Text.Trim()
        $pass = $w.FindName('txtCredPass').Password
        if (-not $name -or -not $user -or -not $pass) {
            [System.Windows.MessageBox]::Show("All fields are required.", "Error", "OK", "Error"); return
        }
        $enc = Encrypt-Credential -user $user -password $pass
        $settings = Load-Settings
        $settings.credentials += [PSCustomObject]@{
            name              = $name
            user              = $enc.user
            encryptedPassword = $enc.encryptedPassword
            key               = $enc.key
        }
        Save-Settings $settings
        Refresh-CredentialsList
        $cmbCredentials.SelectedIndex = $cmbCredentials.Items.Count - 1
        $w.Close()
    })
    $w.ShowDialog() | Out-Null
})

# Connect to vCenter
$btnConnect.Add_Click({
    $vcIdx = $cmbVCenter.SelectedIndex
    $credIdx = $cmbCredentials.SelectedIndex
    if ($vcIdx -lt 0) { [System.Windows.MessageBox]::Show("Select a vCenter.", "Error", "OK", "Error"); return }
    if ($credIdx -lt 0) { [System.Windows.MessageBox]::Show("Select credentials.", "Error", "OK", "Error"); return }

    $settings = Load-Settings
    $vc = $settings.vCenters[$vcIdx]
    $credEntry = $settings.credentials[$credIdx]

    $lblConnectionStatus.Text = "Connecting to $($vc.server)..."
    $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::Yellow
    [System.Windows.Forms.Application]::DoEvents()

    try {
        # Disconnect existing
        if ($global:DefaultVIServers) { $global:DefaultVIServers | Disconnect-VIServer -Confirm:$false -ErrorAction SilentlyContinue }

        Set-PowerCLIConfiguration -Scope Session -DisplayDeprecationWarnings $false -Confirm:$false | Out-Null
        Set-PowerCLIConfiguration -Scope Session -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

        $cred = Decrypt-Credential -credEntry $credEntry
        Connect-VIServer -Server $vc.server -Credential $cred -ErrorAction Stop | Out-Null

        $lblConnectionStatus.Text = "Connected: $($vc.server)"
        $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::LightGreen

        Refresh-ClusterList
    } catch {
        $lblConnectionStatus.Text = "Failed: $_"
        $lblConnectionStatus.Foreground = [System.Windows.Media.Brushes]::Red
    }
})
#endregion

#region Command Set Events
$cmbCommandSet.Add_SelectionChanged({
    $idx = $cmbCommandSet.SelectedIndex
    if ($idx -ge 0 -and $idx -lt $script:commandSets.Count) {
        $cs = $script:commandSets[$idx]
        $lblDescription.Text = "$($cs.type.ToUpper()): $($cs.description)"
        $lstCommands.Items.Clear()
        foreach ($cmd in $cs.commands) { $lstCommands.Items.Add($cmd) | Out-Null }
    }
})

# Trigger initial load
if ($cmbCommandSet.Items.Count -gt 0) {
    $cs = $script:commandSets[0]
    $lblDescription.Text = "$($cs.type.ToUpper()): $($cs.description)"
    $lstCommands.Items.Clear()
    foreach ($cmd in $cs.commands) { $lstCommands.Items.Add($cmd) | Out-Null }
}

# Add New Command Set
$btnAddSet.Add_Click({
    $addXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Add New Command Set" Height="450" Width="550"
        WindowStartupLocation="CenterOwner" Background="#1E1E1E">
    <Grid Margin="15">
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <StackPanel Grid.Row="0" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Name:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtNewName" Width="350" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="1" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Type:" Foreground="#CCCCCC" Width="80"/>
            <ComboBox Name="cmbNewType" Width="120" Background="#2D2D2D" Foreground="#111111" BorderBrush="#3F3F3F">
                <ComboBoxItem Content="list" IsSelected="True"/>
                <ComboBoxItem Content="fix"/>
            </ComboBox>
        </StackPanel>
        <StackPanel Grid.Row="2" Orientation="Horizontal" Margin="0,0,0,8">
            <Label Content="Description:" Foreground="#CCCCCC" Width="80"/>
            <TextBox Name="txtNewDesc" Width="350" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="3" Margin="0,0,0,8">
            <Label Content="Commands (one per line):" Foreground="#CCCCCC"/>
            <TextBox Name="txtNewCommands" AcceptsReturn="True" VerticalScrollBarVisibility="Auto"
                     Height="200" Background="#2D2D2D" Foreground="#CCCCCC" BorderBrush="#3F3F3F"
                     FontFamily="Consolas" FontSize="12" Padding="4"/>
        </StackPanel>
        <StackPanel Grid.Row="4" Orientation="Horizontal" HorizontalAlignment="Right">
            <Button Name="btnSaveNew" Content="Save" Width="80" Margin="0,0,10,0"
                    Background="#0E639C" Foreground="White" BorderBrush="#0E639C" Padding="8,4"/>
            <Button Name="btnCancelNew" Content="Cancel" Width="80"
                    Background="#3F3F3F" Foreground="White" BorderBrush="#3F3F3F" Padding="8,4"/>
        </StackPanel>
    </Grid>
</Window>
"@
    $addReader = New-Object System.Xml.XmlNodeReader ([xml]$addXaml)
    $addWindow = [System.Windows.Markup.XamlReader]::Load($addReader)
    $addWindow.Owner = $window

    $txtNewName     = $addWindow.FindName('txtNewName')
    $cmbNewType     = $addWindow.FindName('cmbNewType')
    $txtNewDesc     = $addWindow.FindName('txtNewDesc')
    $txtNewCommands = $addWindow.FindName('txtNewCommands')
    $btnSaveNew     = $addWindow.FindName('btnSaveNew')
    $btnCancelNew   = $addWindow.FindName('btnCancelNew')

    $btnCancelNew.Add_Click({ $addWindow.Close() })
    $btnSaveNew.Add_Click({
        $name = $txtNewName.Text.Trim()
        $desc = $txtNewDesc.Text.Trim()
        $type = $cmbNewType.Text
        $cmds = $txtNewCommands.Text -split "`r?`n" | Where-Object { $_.Trim() -ne '' }

        if (-not $name) {
            [System.Windows.MessageBox]::Show("Name is required.", "Error", "OK", "Error")
            return
        }
        if ($cmds.Count -eq 0) {
            [System.Windows.MessageBox]::Show("At least one command is required.", "Error", "OK", "Error")
            return
        }

        $newSet = [PSCustomObject]@{
            name        = $name
            type        = $type
            description = $desc
            commands    = @($cmds)
        }

        $script:commandSets += $newSet
        Save-CommandSets $script:commandSets

        $prefix = if ($type -eq 'fix') { '[FIX] ' } else { '[LIST] ' }
        $cmbCommandSet.Items.Add("$prefix$name") | Out-Null
        $cmbCommandSet.SelectedIndex = $cmbCommandSet.Items.Count - 1

        $addWindow.Close()
    })

    $addWindow.ShowDialog() | Out-Null
})
#endregion

#region Run Commands
$btnRun.Add_Click({
    $user     = $txtUser.Text.Trim()
    $password = $txtPassword.Password
    $cluster  = $cmbCluster.SelectedItem
    $csIdx    = $cmbCommandSet.SelectedIndex
    $logPath  = $txtLogPath.Text.Trim()

    if (-not $user)     { [System.Windows.MessageBox]::Show("Enter ESXi username.", "Error", "OK", "Error"); return }
    if (-not $password) { [System.Windows.MessageBox]::Show("Enter ESXi password.", "Error", "OK", "Error"); return }
    if (-not $cluster)  { [System.Windows.MessageBox]::Show("Select a cluster.", "Error", "OK", "Error"); return }
    if ($csIdx -lt 0)   { [System.Windows.MessageBox]::Show("Select a command set.", "Error", "OK", "Error"); return }

    $cs = $script:commandSets[$csIdx]

    if ($cs.type -eq 'fix') {
        $confirm = [System.Windows.MessageBox]::Show(
            "This is a FIX command set that will MODIFY host settings.`nAre you sure you want to proceed?",
            "Confirm Fix Commands", "YesNo", "Warning")
        if ($confirm -ne 'Yes') { return }
    }

    $btnRun.IsEnabled = $false
    $btnStop.IsEnabled = $true
    $txtOutput.Text = ""
    $lblStatus.Content = "Running..."

    $pswdSec = ConvertTo-SecureString -String $password -AsPlainText -Force
    $cred = New-Object System.Management.Automation.PSCredential($user, $pswdSec)

    $code = {
        param(
            [string]$EsxName,
            $cred,
            [string]$CommandTXT
        )
        Import-Module Posh-SSH -ErrorAction Stop
        $ssh = New-SSHSession -ComputerName $EsxName -Credential $cred -AcceptKey -Force 3>$null
        if ($ssh) {
            $result = Invoke-SSHCommand -SessionId $ssh.SessionId -Command $CommandTXT -TimeOut 30 | Select-Object -ExpandProperty Output
            Remove-SSHSession -SessionId $ssh.SessionId | Out-Null
            return $result
        } else {
            return "ERROR: Unable to connect to $EsxName"
        }
    }

    $output = [System.Text.StringBuilder]::new()
    $output.AppendLine("=== SSH Run: $(Get-Date) ===") | Out-Null
    $output.AppendLine("Cluster: $cluster") | Out-Null
    $output.AppendLine("Command Set: $($cs.name)") | Out-Null
    $output.AppendLine("=" * 50) | Out-Null

    try {
        $hosts = Get-Cluster -Name $cluster | Get-VMHost
        $sshHosts = @()

        foreach ($esx in $hosts) {
            $sshSvc = (Get-VMHostService -VMHost $esx).Where({ $_.Key -eq 'TSM-SSH' })
            if ($sshSvc.Running) {
                $sshHosts += $esx
            } else {
                $output.AppendLine("[SKIP] $($esx.Name) - SSH not running") | Out-Null
            }
        }

        if ($sshHosts.Count -eq 0) {
            $output.AppendLine("`nNo hosts with SSH enabled found in cluster '$cluster'.") | Out-Null
            $txtOutput.Text = $output.ToString()
            $lblStatus.Content = "No SSH hosts found"
            $btnRun.IsEnabled = $true
            $btnStop.IsEnabled = $false
            return
        }

        $output.AppendLine("`nRunning on $($sshHosts.Count) host(s)...`n") | Out-Null
        $txtOutput.Text = $output.ToString()
        [System.Windows.Forms.Application]::DoEvents()

        # Check for placeholder values in commands before execution
        $placeholderCmds = $cs.commands | Where-Object { $_ -match $script:placeholderPattern }
        if ($placeholderCmds.Count -gt 0) {
            $phMatches = $placeholderCmds | ForEach-Object { [regex]::Matches($_, $script:placeholderPattern) | ForEach-Object { $_.Value } } | Sort-Object -Unique
            $output.AppendLine("[ERROR] The following commands contain placeholder values that must be replaced before execution:") | Out-Null
            foreach ($phCmd in $placeholderCmds) {
                $output.AppendLine("  > $phCmd") | Out-Null
            }
            $output.AppendLine("`nPlaceholders found: $($phMatches -join ', ')") | Out-Null
            $output.AppendLine("Please edit Configs\Commands.json and replace the placeholder values with actual values.") | Out-Null
            $txtOutput.Text = $output.ToString()
            $lblStatus.Content = "Aborted — placeholder values detected"
            $btnRun.IsEnabled = $true
            $btnStop.IsEnabled = $false
            return
        }

        $jobs = @()
        foreach ($esx in $sshHosts) {
            foreach ($cmd in $cs.commands) {
                $jobs += Start-Job -ScriptBlock $code -Name "SSH-$($esx.Name)" -ArgumentList $esx.Name, $cred, $cmd
            }
        }

        Wait-Job -Job $jobs | Out-Null

        foreach ($job in $jobs) {
            $hostName = $job.Name -replace '^SSH-', ''
            $result = Receive-Job -Job $job 2>&1
            $errors = $job.ChildJobs[0].Error

            $output.AppendLine("--- $hostName ---") | Out-Null
            if ($errors.Count -gt 0) {
                $output.AppendLine("[ERROR] $($errors -join '; ')") | Out-Null
            }
            if ($result) {
                $output.AppendLine(($result | Out-String).Trim()) | Out-Null
            }
            $output.AppendLine("") | Out-Null
        }

        Remove-Job -Job $jobs -Force

        # Save to log
        if ($logPath) {
            $output.ToString() | Out-File $logPath -Force -Encoding UTF8
        }

        $txtOutput.Text = $output.ToString()
        $lblStatus.Content = "Completed - $($sshHosts.Count) hosts, $($jobs.Count) jobs"

    } catch {
        $output.AppendLine("`n[EXCEPTION] $_") | Out-Null
        $txtOutput.Text = $output.ToString()
        $lblStatus.Content = "Error: $_"
    }

    $btnRun.IsEnabled = $true
    $btnStop.IsEnabled = $false
})
#endregion

$window.ShowDialog() | Out-Null
