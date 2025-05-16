# VERSION: 0.1
# Key generator for EasyIO devices in PowerShell
# This script loops over a directory of backup files and generates keys
# named according to the cloud name for the publishing device

param (
    [string]$BackupDirectory,
    [string]$KeysDirectory
)

# Function to check if directories exist
function Check-Directories {
    param([string[]]$Dirs)
    foreach ($Dir in $Dirs) {
        if (-Not (Test-Path -Path $Dir -PathType Container)) {
            Write-Host "$Dir does not exist, quitting."
            exit 1
        }
    }
}

# Ensure required arguments are provided
if ($BackupDirectory -eq "" -or $KeysDirectory -eq "") {
    Write-Host "Usage: script.ps1 [backup_project_directory] [keys_directory]"
    exit 1
}

Check-Directories -Dirs @($BackupDirectory, $KeysDirectory)

# Ensure the keys directory is empty or only contains CA files
$existingKeys = Get-ChildItem -Path $KeysDirectory | Where-Object { $_.Name -notmatch '^CA.*' }
if ($existingKeys.Count -gt 0) {
    Write-Host "STOP: keys directory already contains keys."
    exit 1
}

# Function to identify the device name
function Identify-DeviceName {
    param([string]$ExpandedDir)
    $ParameterFile = "$ExpandedDir\cpt\plugins\DataServiceConfig\data_mapping.json"
    
    if (Test-Path $ParameterFile) {
        $DeviceName = Select-String -Path $ParameterFile -Pattern '"device_id":"([^"]+)"' | 
                      ForEach-Object { $_.Matches.Groups[1].Value } | Select-Object -First 1
        return $DeviceName
    } else {
        return $null
    }
}

# Function to generate keys
function Generate-Key {
    param([string]$KeysDir, [string]$DeviceName)

    $PrivateKey = "rsa_private$DeviceName.pem"
    $PublicKey = "rsa_public$DeviceName.pem"

    & ssh-keygen -b 2048 -t rsa -f "$KeysDir\newkey" -q -N "" | Out-Null
    if ($?) {
        Move-Item -Path "$KeysDir\newkey" -Destination "$KeysDir\$PrivateKey"
        Move-Item -Path "$KeysDir\newkey.pub" -Destination "$KeysDir\$PublicKey"
    } else {
        Write-Host "ERROR: Failed to generate new key for $DeviceName."
    }
}

Write-Host "Processing EasyIO backup files in $BackupDirectory..."

foreach ($DeviceDir in Get-ChildItem -Path $BackupDirectory -Directory) {
    if ($DeviceDir.Name -match '^\d+\.\d+\.\d+\.\d+$') {
        $BackupFiles = Get-ChildItem -Path $DeviceDir.FullName -Filter "*.tgz" | Sort-Object Name -Descending
        if ($BackupFiles.Count -gt 0) {
            $LatestBackup = $BackupFiles[0].Name
            
            # Extract the backup
            tar -xz -C $DeviceDir.FullName -f "$DeviceDir\$LatestBackup"

            # Find the root directory of the expanded backup
            $ExpandedRootDir = Get-ChildItem -Path $DeviceDir.FullName -Directory | Select-Object -First 1

            if ($ExpandedRootDir) {
                $DeviceName = Identify-DeviceName -ExpandedDir $ExpandedRootDir.FullName
                if ($DeviceName) {
                    Generate-Key -KeysDir $KeysDirectory -DeviceName $DeviceName
                    Remove-Item -Recurse -Force $ExpandedRootDir.FullName
                    Write-Host "$DeviceDir\$LatestBackup -> $DeviceName key made."
                } else {
                    Write-Host "ERROR: Failed to identify device name."
                }
            }
        } else {
            Write-Host "WARNING: No backup file found for $DeviceDir, skipping!"
        }
    }
}

Write-Host "Finished."


