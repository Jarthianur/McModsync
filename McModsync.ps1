using namespace System.Windows
using namespace System

$ErrorActionPreference = "Stop"
$baseDir = ''
$tmpDir = ''
$modsToSync = @()

[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Drawing")
[void] [System.Reflection.Assembly]::LoadWithPartialName("System.Windows.Forms")

Function Get-InstallationDir ($Partition) {
    $dir = Get-ChildItem -Path $Partition`:\ -Include MinecraftLauncher.exe -File -Recurse -Depth 1 -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-Not $dir) {
        throw "Minecraft directory not found."
    }
    $dir.DirectoryName
}

Function Get-Remote-Listing ($ServerBase, $LocalDir, $Version, $Theme) {
    [void] (Invoke-WebRequest -Uri "$ServerBase/$Version/$Theme/.listing" -OutFile "$LocalDir\.listing")
    "$LocalDir\.listing"
}

Function Get-Remote-File ($ServerBase, $LocalDir, $Path, $File) {
    [void] (Invoke-WebRequest -Uri "$ServerBase/$Path/$File" -OutFile "$LocalDir\$File")
}

Function Get-Remote-Mod($ServerBase, $LocalDir, $Version, $Theme, $Mod) {
    Invoke-WebRequest -Uri "$ServerBase/$Version/$Theme/$Mod" -OutFile "$LocalDir\$Mod"
}

Function Get-ThemesFromInfo ($Info) {
    $themes = @()
    foreach ($line in Get-Content $Info) {
        $themes += $line
    }
    $themes
}

Function Get-ModsFromListing ($Listing) {
    $mods = @{ }
    foreach ($line in Get-Content $Listing) {
        $info = $line.Split(":")
        $mod = New-Object -TypeName psobject -Property @{
            Name    = $info[0]
            Version = $info[1]
            Action  = "NONE"
        }
        $mods.Add($mod.Name, $mod)
    }
    $mods
}

Function Compare-Mods ($LocalMods, $RemoteMods) {
    $sync = @()
    $RemoteMods.GetEnumerator() | ForEach-Object {
        if (-Not $LocalMods.ContainsKey($_.Value.Name)) {
            $_.Value.Action = "ADD"
            $sync += $_.Value
        }
        elseif ($LocalMods[$_.Value.Name].Version -ne $_.Value.Version) {
            $_.Value.Action = "UPDATE"
            $sync += $_.Value
        }
    }
    $LocalMods.GetEnumerator() | ForEach-Object {
        if (-Not $RemoteMods.ContainsKey($_.Value.Name)) {
            $_.Value.Action = "DEL"
            $sync += $_.Value
        }
    }
    $sync
}

# Window
$form = New-Object Forms.Form
$form.BackColor = "white"
$form.StartPosition = "CenterScreen"
$form.Width = 600
$form.Text = "Minecraft Mod Sync"
$form.AutoSize = $true
$form.AutoScroll = $false
$form.Icon = [Drawing.Icon]::ExtractAssociatedIcon("$PSHOME\powershell.exe")

# Layout
$layout = New-Object Forms.Panel
$layout.AutoSize = $true
$layout.AutoScroll = $false
$layout.Dock = [Forms.DockStyle]::Fill
$layout.Padding = 8
$form.Font = New-Object Drawing.Font("DefaultFont", 10, [Drawing.FontStyle]::Regular)
$form.Controls.Add($layout)

$controls = @()

# OK
$btnPanel = New-Object Forms.Panel
$btnPanel.Dock = [Forms.DockStyle]::Bottom
$btnPanel.Height = 30

$syncBtn = New-Object Forms.Button
$syncBtn.Text = 'Sync'
$syncBtn.BackColor = 'lightgray'
$syncBtn.Dock = [Forms.DockStyle]::Right
$syncBtn.AutoSize = $true

$checkBtn = New-Object Forms.Button
$checkBtn.Text = 'Check'
$checkBtn.BackColor = 'lightgray'
$checkBtn.Dock = [Forms.DockStyle]::Right
$checkBtn.AutoSize = $true

$btnPanel.Controls.Add($checkBtn)
$btnPanel.Controls.Add($syncBtn)

$layout.Controls.Add($btnPanel)

# Directory
$dirPanel = New-Object Forms.Panel
$dirPanel.BorderStyle = [Forms.BorderStyle]::Fixed3D
$dirPanel.Padding = 4
$dirPanel.Dock = [Forms.DockStyle]::Top
$dirPanel.AutoSize = $true

$dirLabel = New-Object Forms.Label
$dirLabel.AutoSize = $true
$dirLabel.Dock = [Forms.DockStyle]::Top
$dirLabel.Text = 'Directory'
$dirLabel.Padding = '4,8,0,2'

$dirTlp = New-Object Forms.TableLayoutPanel
$dirTlp.RowCount = 2
$dirTlp.ColumnCount = 2
$dirTlp.RowStyles.Clear()
[void]($dirTlp.RowStyles.Add((New-Object Forms.RowStyle([Forms.SizeType]::AutoSize))))
$dirTlp.ColumnStyles.Clear()
[void]($dirTlp.ColumnStyles.Add((New-Object Forms.ColumnStyle([Forms.SizeType]::Percent, 80))))
[void]($dirTlp.ColumnStyles.Add((New-Object Forms.ColumnStyle([Forms.SizeType]::Percent, 20))))
$dirTlp.Dock = [Forms.DockStyle]::Fill
$dirTlp.Padding = 2
$dirTlp.AutoSize = $true

$dirSelect = New-Object Forms.ComboBox
$dirSelect.AutoSize = $true
$dirSelect.Dock = [Forms.DockStyle]::Top
$dirSelect.Items.AddRange((Get-Volume | Where-Object { $_.FileSystemType -eq 'NTFS' -and -Not [string]::IsNullOrEmpty($_.DriveLetter) } | Select-Object -ExpandProperty DriveLetter))
$dirSelect.SelectedIndex = 0

$dirText = New-Object Forms.TextBox
$dirText.Dock = [Forms.DockStyle]::Top
$dirText.Text = 'C:\'
$dirText.AutoSize = $true

$dirSetBtn = New-Object Forms.Button
$dirSetBtn.Text = 'Select'
$dirSetBtn.Dock = [Forms.DockStyle]::Top
$dirSetBtn.BackColor = 'lightgray'
$dirSetBtn.AutoSize = $true
$dirSetBtn.Add_Click( {
        $script:baseDir = $dirText.Text
        $script:tmpDir = "$baseDir\tmp"
        if (-Not (Test-Path -Path "$tmpDir")) {
            [void] (New-Item -ItemType Directory -Path "$tmpDir")
        }
    })

$dirDiscoverBtn = New-Object Forms.Button
$dirDiscoverBtn.Text = 'Search'
$dirDiscoverBtn.Dock = [Forms.DockStyle]::Top
$dirDiscoverBtn.BackColor = 'lightgray'
$dirDiscoverBtn.AutoSize = $true
$dirDiscoverBtn.Add_Click( {
        try {
            $script:dirText.Text = Get-InstallationDir -Partition $dirSelect.SelectedItem
            $dirSetBtn.PerformClick()
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Something went wrong: $_", "ERROR", 5, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

$dirTlp.Controls.Add($dirSelect, 0, 0)
$dirTlp.Controls.Add($dirDiscoverBtn, 1, 0)
$dirTlp.Controls.Add($dirText, 0, 1)
$dirTlp.Controls.Add($dirSetBtn, 1, 1)

$dirPanel.Controls.Add($dirTlp)

# modpack/server
$versionPanel = New-Object Forms.Panel
$versionPanel.AutoSize = $true
$versionPanel.Padding = 4
$versionPanel.Dock = [Forms.DockStyle]::Top
$versionPanel.BorderStyle = [Forms.BorderStyle]::Fixed3D

$versionLabel = New-Object Forms.Label
$versionLabel.AutoSize = $true
$versionLabel.Dock = [Forms.DockStyle]::Top
$versionLabel.Text = 'Server Base Path / Modpack'
$versionLabel.Padding = '4,8,0,2'

$versionTlp = New-Object Forms.TableLayoutPanel
$versionTlp.RowCount = 2
$versionTlp.ColumnCount = 2
$versionTlp.RowStyles.Clear()
[void]($versionTlp.RowStyles.Add((New-Object Forms.RowStyle([Forms.SizeType]::AutoSize))))
$versionTlp.ColumnStyles.Clear()
[void]($versionTlp.ColumnStyles.Add((New-Object Forms.ColumnStyle([Forms.SizeType]::Percent, 80))))
[void]($versionTlp.ColumnStyles.Add((New-Object Forms.ColumnStyle([Forms.SizeType]::Percent, 20))))
$versionTlp.Dock = [Forms.DockStyle]::Fill
$versionTlp.Padding = 2
$versionTlp.AutoSize = $true

$versionServer = New-Object Forms.TextBox
$versionServer.Dock = [Forms.DockStyle]::Top
$versionServer.AutoSize = $true
$versionServer.Text = ''

$versionSelect = New-Object Forms.ComboBox
$versionSelect.Dock = [Forms.DockStyle]::Top
$versionSelect.AutoSize = $true

$versionFetchBtn = New-Object Forms.Button
$versionFetchBtn.Text = 'Fetch'
$versionFetchBtn.Dock = [Forms.DockStyle]::Top
$versionFetchBtn.BackColor = 'lightgray'
$versionFetchBtn.AutoSize = $true
$versionFetchBtn.Add_Click( {
        try {
            $serverBase = $versionServer.Text
            Get-Remote-File -ServerBase "$serverBase" -LocalDir "$tmpDir" -Path "" -File ".info"
            $themes = Get-ThemesFromInfo -Info "$tmpDir\.info"
            $versionSelect.Items.AddRange($themes)
            $versionSelect.SelectedIndex = 0
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Something went wrong: $_", "ERROR", 5, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

$versionTlp.Controls.Add($versionServer, 0, 0)
$versionTlp.Controls.Add($versionFetchBtn, 1, 0)
$versionTlp.Controls.Add($versionSelect, 0, 1)

$versionPanel.Controls.Add($versionTlp)

# checks
$checkLabel = New-Object Forms.Label
$checkLabel.AutoSize = $true
$checkLabel.Dock = [Forms.DockStyle]::Top
$checkLabel.Text = 'Components'
$checkLabel.Padding = '4,8,0,2'

$checkPanel = New-Object Forms.FlowLayoutPanel
$checkPanel.FlowDirection = 'LeftToRight'
$checkPanel.Padding = 4
$checkPanel.Dock = [Forms.DockStyle]::Top
$checkPanel.AutoSize = $true
$checkPanel.BorderStyle = [Forms.BorderStyle]::Fixed3D

$checkMods = New-Object Forms.CheckBox
$checkMods.Text = 'Mods'
$checkMods.AutoSize = $true

$checkResources = New-Object Forms.CheckBox
$checkResources.Text = 'Resourcepacks'
$checkResources.AutoSize = $true

$checkShaders = New-Object Forms.CheckBox
$checkShaders.Text = 'Shader'
$checkShaders.AutoSize = $true

$checkForge = New-Object Forms.CheckBox
$checkForge.Text = 'Forge'
$checkForge.AutoSize = $true

$checkPanel.Controls.Add($checkMods)
$checkPanel.Controls.Add($checkForge)
$checkPanel.Controls.Add($checkResources)
$checkPanel.Controls.Add($checkShaders)

# diff
$diffLabel = New-Object Forms.Label
$diffLabel.AutoSize = $true
$diffLabel.Dock = [Forms.DockStyle]::Top
$diffLabel.Text = 'Actions'
$diffLabel.Padding = '4,8,0,2'

$diffPanel = New-Object Forms.DataGridView
$diffPanel.Dock = [Forms.DockStyle]::Top
$diffPanel.BorderStyle = [Forms.BorderStyle]::Fixed3D
$diffPanel.ReadOnly = $true
$diffPanel.AutoSizeColumnsMode = [Forms.DataGridViewAutoSizeColumnMode]::Fill
$diffPanel.AutoSizeRowsMode = [Forms.DataGridViewAutoSizeRowsMode]::AllCells
$diffPanel.RowHeadersVisible = $false
$diffPanel.CellBorderStyle = 'none'
$diffPanel.ColumnCount = 4
$diffPanel.ColumnHeadersVisible = $true
$diffPanel.Columns[0].Name = 'Name'
$diffPanel.Columns[1].Name = 'Local Version'
$diffPanel.Columns[2].Name = 'Remote Version'
$diffPanel.Columns[3].Name = 'Action'

$controls += $diffPanel
$controls += $diffLabel
$controls += $checkPanel
$controls += $checkLabel
$controls += $versionPanel
$controls += $versionLabel
$controls += $dirPanel
$controls += $dirLabel
    
foreach ($c in $controls) {
    $layout.Controls.Add($c)
}

$checkBtn.Add_Click( {
        try {
            $serverBase = $versionServer.Text
            $info = $versionSelect.SelectedItem.Split(":")
            $remoteListing = Get-Remote-Listing -ServerBase "$serverBase" -LocalDir "$tmpDir" -Version $info[0] -Theme $info[1]
            $localListing = "$baseDir\mods\.listing"

            if (-Not (Test-Path "$baseDir\mods")) {
                try {
                    [void](New-Item -ItemType Directory -Path "$baseDir\mods")
                }
                catch {
                    throw "Could not create directory [$baseDir\mods]. (Cause: $_)"
                }
            }

            if (-Not (Test-Path "$localListing")) {
                try {
                    [void](New-Item -ItemType File -Path "$localListing")
                }
                catch {
                    throw "Could not create file [$localListing]. (Cause: $_)"
                }
            }

            $remoteMods = Get-ModsFromListing -Listing $remoteListing
            $localMods = Get-ModsFromListing -Listing $localListing
            $script:modsToSync = Compare-Mods -LocalMods $localMods -RemoteMods $remoteMods
            $diffPanel.Rows.Clear()

            foreach ($mod in $modsToSync) {
                $diffPanel.Rows.Add($mod.Name, $localMods[$mod.Name].Version, $mod.Version, $mod.Action)
            }
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Something went wrong: $_", "ERROR", 5, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

$syncBtn.Add_Click( {
        try {
            $serverBase = $versionServer.Text
            $info = $versionSelect.SelectedItem.Split(":")

            if ($checkMods.Checked) {
                foreach ($mod in $modsToSync) {
                    if ($mod.Action -eq "ADD" -or $mod.Action -eq "UPDATE") {
                        Get-Remote-Mod -ServerBase "$serverBase" -LocalDir "$baseDir\mods" -Version $info[0] -Theme $info[1] -Mod $mod.Name
                    }
                    elseif ($mod.Action -eq "DEL") {
                        $path = "$baseDir\mods\" + $mod.Name
                        Remove-Item -Path "$path"
                    }
                }
                Copy-Item -Path "$tmpDir\.listing" -Destination "$baseDir\mods\.listing"
            }
        
            if ($checkResources.Checked) {
                Get-Remote-File -ServerBase "$serverBase" -LocalDir "$tmpDir" -Path "" -File "resourcepacks.zip"
                if ((Test-Path "$baseDir\resourcepacks")) {
                    Remove-Item -Path -Recurse "$baseDir\resourcepacks"
                }
                Expand-Archive -Path "$tmpDir\resourcepacks.zip" -DestinationPath "$baseDir"
                Remove-Item -Path "$tmpDir\resourcepacks.zip"
            }

            if ($checkShaders.Checked) {
                Get-Remote-File -ServerBase "$serverBase" -LocalDir "$tmpDir" -Path "" -File "shaderpacks.zip"
                if ((Test-Path "$baseDir\shaderpacks")) {
                    Remove-Item -Path -Recurse "$baseDir\shaderpacks"
                }
                Expand-Archive -Path "$tmpDir\shaderpacks.zip" -DestinationPath "$baseDir"
                Remove-Item -Path "$tmpDir\shaderpacks.zip"
            }

            if ($checkForge.Checked) {
                $path = $info[0] + "/" + $info[1]
                Get-Remote-File -ServerBase "$serverBase" -LocalDir "$tmpDir" -Path "$path" -File "forge-installer.exe"
            }

            [System.Windows.Forms.MessageBox]::Show("Success", "", 0, [System.Windows.Forms.MessageBoxIcon]::Information)
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Something went wrong: $_", "ERROR", 5, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    })

[void] $form.ShowDialog()
[void] $form.BringToFront()
