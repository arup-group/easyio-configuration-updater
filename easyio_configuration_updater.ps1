# VERSION: 0.4
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory
# TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT

param(
    [string]$BackupProjectDirectory,
    [string]$OutputProjectDirectory,
    [string]$KeysDirectory
)

# Check that all required parameters are provided
if (-not $BackupProjectDirectory -or -not $OutputProjectDirectory -or -not $KeysDirectory) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [backup_project_directory] [output_project_directory] [keys_directory]"
    exit 1
}

# Check that the provided directories exist
foreach ($dir in $BackupProjectDirectory, $OutputProjectDirectory, $KeysDirectory) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        Write-Host "$dir does not exist, quitting." | Write-Error
        exit 1
    }
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

function Update-CloudSettings {
    param (
        [string]$ExpandedBackupRoot,
        [string]$DeviceName
    )

    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    (Get-Content $OldFile) -replace '"essential-keep-197822"', '"bos-platform-prod"' `
        -replace '"mqtt.googleapis.com"', '"mqtt.bos.goog"' `
        -replace '"rsa_private[A-Z0-9]*\.pem"', "`"rsa_private$DeviceName.pem`"" `
        -replace '"rsa_public[A-Z0-9]*\.pem"', "`"rsa_public$DeviceName.pem`"" | Set-Content $NewFile

    # In Powershell, we can't rename a file onto a destination that already exists, so use 'Move-Item' instead    
    Move-Item -Path $NewFile -Destination $OldFile -Force
}

function Update-Keys {
    param (
        [string]$ExpandedBackupRoot,
        [string]$DeviceName
    )

    $KeysPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig\uploads\certs"
    $PrivateKey = "rsa_private$DeviceName.pem"
    $PublicKey = "rsa_public$DeviceName.pem"
    $CAFile = "CA File.pem"

    # Clear old keys
    Remove-Item "$KeysPath\*" -Force -ErrorAction SilentlyContinue

    # Copy new ones
    Copy-Item "$KeysDirectory\$PrivateKey" "$KeysPath\$PrivateKey"
    Copy-Item "$KeysDirectory\$PublicKey" "$KeysPath\$PublicKey"
    Copy-Item "$KeysDirectory\$CAFile" "$KeysPath\$CAFile"
}

Write-Host "Processing EasyIO backup files in $BackupProjectDirectory..."

foreach ($DeviceDirectory in Get-ChildItem -Path $BackupProjectDirectory -Directory) {
    if ($DeviceDirectory.Name -match '^\d+\.\d+\.\d+\.\d+$') {

        # Save names of input and output directories, and backup file name, as strings
        $InputDeviceDirectory = "$BackupProjectDirectory\$($DeviceDirectory.Name)"
        $OutputDeviceDirectory = "$OutputProjectDirectory\$($DeviceDirectory.Name)"
        $LatestBackup = (Get-ChildItem "$BackupProjectDirectory\$($DeviceDirectory.Name)\*.tgz" | Sort-Object Name | Select-Object -Last 1).Name
        
        # If we've got a valid archive file, then process it
        if (Test-Path -Path "$InputDeviceDirectory\$LatestBackup" -PathType Leaf) {

            # Create an output folder for the device, if it doesn't exist already
            if (-not (Test-Path -Path $OutputDeviceDirectory)) {
                New-Item -ItemType Directory -Path $OutputDeviceDirectory | Out-Null
            }

            # Expand the archive into the output project folder
            tar -xz -C "$OutputDeviceDirectory" -f "$InputDeviceDirectory\$LatestBackup"

            # Get the root directory
            $ExpandedRootDir = (Get-ChildItem -Path $OutputDeviceDirectory -Directory | Select-Object -First 1).Name

            # Make the changes and then re-archive the directory with a new name
            if ($ExpandedRootDir) {
                $DeviceName = Identify-DeviceName "$OutputDeviceDirectory\$ExpandedRootDir"
                Update-CloudSettings "$OutputDeviceDirectory\$ExpandedRootDir" $DeviceName
                Update-Keys "$OutputDeviceDirectory\$ExpandedRootDir" $DeviceName

                Rename-Item -Path "$OutputDeviceDirectory\$ExpandedRootDir" -NewName "updated_backup"
                tar -czf "$OutputDeviceDirectory\updated_backup.tgz" -C "$OutputDeviceDirectory" "updated_backup" 
                Remove-Item "$OutputDeviceDirectory\updated_backup" -Recurse -Force
            }

            # Report on success or fail
            if (Test-Path -Path "$OutputDeviceDirectory\updated_backup.tgz" -PathType Leaf) {
                Write-Host "$InputDeviceDirectory\$LatestBackup  ->  $OutputDeviceDirectory\updated_backup.tgz"
            }
            else {
                Write-Host "ERROR: Failed to write $OutputDeviceDirectory\updated_backup.tgz." | Write-Error
            }
        }
        else {
            Write-Host "WARNING: No backup file found for $InputDeviceDirectory, skipping!" | Write-Error
        }
    }
}

Write-Host "Finished."


