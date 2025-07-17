# VERSION: 0.1
# Key generator for EasyIO devices in PowerShell
# This script loops over a directory of backup files and generates keys
# named according to the cloud name for the publishing device

param (
    [string]$BackupProjectDirectory,
    [string]$KeysDirectory
)

# Function to check if directories exist
function Check-Directories {
    param([string[]]$Dirs)
    foreach ($Dir in $Dirs) {
        if (-Not (Test-Path -Path $Dir -PathType Container)) {
            Write-Host "$Dir does not exist, quitting." | Write-Error
            exit 1
        }
    }
}

# Ensure required arguments are provided
if ($BackupProjectDirectory -eq "" -or $KeysDirectory -eq "") {
    Write-Host "Usage: script.ps1 [backup_project_directory] [keys_directory]"
    exit 0
}

Check-Directories -Dirs @($BackupProjectDirectory, $KeysDirectory)

# Ensure the keys directory is empty or only contains CA files
$existingKeys = Get-ChildItem -Path $KeysDirectory | Where-Object { $_.Name -notmatch '^CA.*' }
if ($existingKeys.Count -gt 0) {
    Write-Host "STOP: keys directory already contains keys." | Write-Error
    exit 1
}

# Function to identify the device name
function Identify-DeviceName {
    param (
        [string]$ExpandedArchivePath
    )
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"

    $DeviceName = Select-String -Path $ParameterFile -Pattern '"device_id":"([^"]+)"' | % {$_.matches.groups[1].value} | Select-Object -First 1
    return $DeviceName
}

# Function to generate keys
function Generate-Key {
    param([string]$KeysDir, [string]$DeviceName)

    $PrivateKey = "rsa_private$DeviceName.pem"
    $PublicKey = "rsa_public$DeviceName.pem"

    & ssh-keygen -b 2048 -t rsa-sha2-256 -f "$KeysDir\newkey" -q -N `"`" | Out-Null
    if ($?) {
        Move-Item -Path "$KeysDir\newkey" -Destination "$KeysDir\$PrivateKey" -Force
        Move-Item -Path "$KeysDir\newkey.pub" -Destination "$KeysDir\$PublicKey" -Force
    } else {
        Write-Host "ERROR: Failed to generate new key for $DeviceName." | Write-Error
    }
}

Write-Host "Processing EasyIO backup files in $BackupProjectDirectory..."

foreach ($DeviceDirectory in Get-ChildItem -Path $BackupProjectDirectory -Directory) {
    if ($DeviceDirectory.Name -match '^\d+\.\d+\.\d+\.\d+$') {

        # Save names of input directory, and backup file name, as strings
        $InputDeviceDirectory = "$BackupProjectDirectory\$($DeviceDirectory.Name)"
        $LatestBackup = (Get-ChildItem -Path "$BackupProjectDirectory\$($DeviceDirectory.Name)" -Filter "*.tgz" | Sort-Object Name | Select-Object -Last 1).Name

        # If we've got a valid archive file, then process it
        if (Test-Path -Path "$InputDeviceDirectory\$LatestBackup" -PathType Leaf) {
  
            # Extract the backup
            tar -xz -C $InputDeviceDirectory -f "$InputDeviceDirectory\$LatestBackup"

            # Get the root directory
            $ExpandedRootDir = (Get-ChildItem -Path $InputDeviceDirectory -Directory | Select-Object -First 1).Name

            # Find the device name, make a new key pair then delete the expanded directory
            if ($ExpandedRootDir) {
                $DeviceName = Identify-DeviceName "$InputDeviceDirectory\$ExpandedRootDir"
                if ($DeviceName) {
                    Generate-Key -KeysDir $KeysDirectory -DeviceName $DeviceName
                    Remove-Item "$InputDeviceDirectory\$ExpandedRootDir" -Recurse -Force
                    Write-Host "$InputDeviceDirectory\$LatestBackup -> $DeviceName key made."
                } else {
                    Write-Host "ERROR: Failed to identify device name." | Write-Error
                }
            } else {
                Write-Host "ERROR: Failed to expand or find archive root directory." | Write-Error
            }

        } else {
            Write-Host "WARNING: No backup file found for $DeviceDir, skipping!" | Write-Error
        }
    }
}
 

Write-Host "Finished."


