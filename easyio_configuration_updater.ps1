# VERSION: 0.6
# Key and config rotator for EasyIO devices
# This script loops over a directory of backup files and puts modified backup files
# into an output directory.
#
# TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT
#
# Be aware that Powershell, especially old versions, can corrupt Unix text files by
# using CRLF at line endings or inserting a byte-order mark (BOM) at the beginning
# of the file. This behaviour is possible on Powershell 5.1 (Windows 10) even with UTF8
# output encoding, and the script therefore has parameters to remove BOM and translate
# CRLF to LF when writing files.

param(
    [string]$BackupProjectDirectory,
    [string]$OutputProjectDirectory,
    [string]$KeysDirectory
)

# Check that all required parameters are provided
if (-not $BackupProjectDirectory -or -not $OutputProjectDirectory) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [backup_project_directory] [output_project_directory] [keys_directory]"
    exit 1
}

# Check if optional keys directory is provided
if (-not $KeysDirectory) {
    Write-Host "Note: keys directory not provided, existing keys in backups will be retained."
}

# Check that the provided directories exist on valid paths
foreach ($dir in $BackupProjectDirectory, $OutputProjectDirectory, $KeysDirectory) {
    if ($dir -and -not (Test-Path -Path $dir -PathType Container)) {
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

    # The -Encoding utf8 causes Powershell to use Unix-type line endings and will not have a BOM
    # from Powershell version 6 onwards. For older Powershell (shipped with Windows 10), use -Encoding ASCII
    # to prevent the BOM from being inserted
    (Get-Content $OldFile) -replace '"essential-keep-197822"', '"bos-platform-prod"' `
        -replace '"mqtt.googleapis.com"', '"mqtt.bos.goog"' `
        -replace "`r`n", "`n" `
        | Out-File -FilePath $NewFile -Encoding ascii -NoNewLine

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

    # Update key references in configuration file
    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    # The -Encoding utf8 causes Powershell to use Unix-type line endings and will not have a BOM
    # from Powershell version 6 onwards. For older Powershell (shipped with Windows 10), use -Encoding ASCII
    # to prevent the BOM from being inserted
    (Get-Content $OldFile) -replace '"rsa_private[A-Z0-9]*\.pem"', "`"rsa_private$DeviceName.pem`"" `
        -replace '"rsa_public[A-Z0-9]*\.pem"', "`"rsa_public$DeviceName.pem`"" `
        -replace "`r`n", "`n" `
        | Out-File -FilePath $NewFile -Encoding ascii -NoNewLine

    # In Powershell, we can't rename a file onto a destination that already exists, so use 'Move-Item' instead    
    Move-Item -Path $NewFile -Destination $OldFile -Force
}

function Update-TimeSettings {
    param (
        [string]$ExpandedBackupRoot
    )

    # Define the new content for time.dat
    $newTimeDat = @"
UTC Offset:0
Time Zone:Etc/UTC
DST Offset:0
DST Start On:-1
DST Start Date:1,0
DST Start Time:0,0
DST End On:-1
DST End Date:1,0
DST End Time:0,0

"@

    # Directory and file for firmware data expansion
    $firmwareDir = "$ExpandedBackupRoot\firmware_data"
    $firmwareTar = "$ExpandedBackupRoot\firmware_data.tar"

    try {
        # Create the temporary directory
        New-Item -ItemType Directory -Path $firmwareDir -ErrorAction Stop | Out-Null

        # Extract the firmware archive into the temporary directory
        tar -x -C $firmwareDir -f $firmwareTar

        # Replace time.dat with the new configuration, using Unix-style line endings
        ($newTimeDat) -replace "`r`n", "`n" `
            | Out-File -FilePath "$firmwareDir\time.dat" -Encoding ascii -NoNewLine

        # Recompress the firmware directory into firmware_data.tar
        tar -cf $firmwareTar -C $firmwareDir .

        # Remove the temporary directory
        Remove-Item -Recurse -Force $firmwareDir
    }
    catch {
        Write-Error "ERROR: Failed to update time.dat file. $_"
    }
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
                if ($KeysDirectory) {
                    Update-Keys "$OutputDeviceDirectory\$ExpandedRootDir" $DeviceName
                }
                Update-TimeSettings "$OutputDeviceDirectory\$ExpandedRootDir"

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


