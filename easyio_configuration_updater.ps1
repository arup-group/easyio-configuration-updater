# VERSION: 0.8
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
    [string]$ParameterFile
)

if (-not $ParameterFile) {
    Write-Host "Usage: $($MyInvocation.MyCommand.Name) [parameter_file]"
    exit 1
}

foreach ($line in Get-Content "$ParameterFile") {
    if ($line -match '=') {
        Invoke-Expression "$line"
    }
}

# Check that all required parameters are provided
foreach ($parameter_name in "BackupProjectDirectory", "OutputProjectDirectory", "KeysDirectory", `
             "project_id", "registry_id", "region_id", "mqtt_host_id", "ca_file_name") {
    $parameter_value = $(Get-Variable -Name $parameter_name -ValueOnly)
    if (-not $parameter_value -or $parameter_value -eq "") {
        Write-Host "Parameter is not defined: $parameter_name"
        if (-not $parameter_name -eq "KeysDirectory") {
            Write-Host "Quitting."
            exit 1
        }
        else {
            Write-Host "Note: keys directory not provided, existing keys in backups will be retained."
        }
    }
}

# Check that the provided directories exist on valid paths
foreach ($dir in $BackupProjectDirectory, $OutputProjectDirectory, $KeysDirectory) {
    if ($dir -and -not (Test-Path -Path $dir -PathType Container)) {
        Write-Host "$dir does not exist, quitting." | Write-Error
        exit 1
    }
}

Write-Host "Using parameters:"
Write-Host "backup project directory:     $BackupProjectDirectory"
Write-Host "output project directory:     $OutputProjectDirectory"
Write-Host "keys directory:               $KeysDirectory"
Write-Host "project_id:                   $project_id"
Write-Host "registry_id:                  $registry_id"
Write-Host "region_id:                    $region_id"
Write-Host "mqtt_host:                    $mqtt_host_id"
Write-Host "ca_file:                      $ca_file_name"

exit 1

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
        [string]$rootDir,
        [string]$project_id,
        [string]$registry_id,
        [string]$region_id,
        [string]$mqtt_host_id,
        [string]$ca_file_name
    )

    $configurationPath = Join-Path $rootDir 'cpt/plugins/DataServiceConfig'
    $jsonFile = Join-Path $configurationPath 'data_mapping.json'
    $backupFile = Join-Path $configurationPath 'data_mapping.old.json'

    # Read JSON file contents
    $content = Get-Content $jsonFile -Raw

    # Apply substitutions
    $content = $content -replace '"project_id":"[^"]+"', "`"project_id`":`"$project_id`""
    $content = $content -replace '"registry_id":"[^"]+"', "`"registry_id`":`"$registry_id`""
    $content = $content -replace '"region":"[^"]+"', "`"region`":`"$region_id`""
    $content = $content -replace '"mqtt_host":"[^"]+"', "`"mqtt_host`":`"$mqtt_host_id`""
    $content = $content -replace '"key_file":"[^A-Z0-9]+([A-Z0-9\-]+)\.pem"', '"key_file":"rsa_private_$1.pem"'
    $content = $content -replace '"cert_file":"[^A-Z0-9]+([A-Z0-9\-]+)\.pem"', '"cert_file":"rsa_cert_$1.pem"'
    $content = $content -replace '"ca_file":"[^"]+"', "`"ca_file`":`"$ca_file_name`""

    # Backup original file and write new content
    Move-Item -Path $jsonFile -Destination $backupFile -Force
    $content | Set-Content -Path $jsonFile
    Remove-Item -Path $backupFile -Force
}



function Update-CloudSettings {
    param (
        [string]$ExpandedBackupRoot,
        [string]$DeviceName
    )
    # This function also uses global variables project_id, registry_id, region_id, mqtt_host_id
    # ca_file_name

    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    # Read JSON file contents
    $content = Get-Content $OldFile -Raw

    # Apply substitutions
    $content = $content -replace '"project_id":"[^"]+"', "`"project_id`":`"$project_id`""
    $content = $content -replace '"registry_id":"[^"]+"', "`"registry_id`":`"$registry_id`""
    $content = $content -replace '"region":"[^"]+"', "`"region`":`"$region_id`""
    $content = $content -replace '"mqtt_host":"[^"]+"', "`"mqtt_host`":`"$mqtt_host_id`""
    $content = $content -replace '"key_file":"[^A-Z0-9]+([A-Z0-9\-]+)\.pem"', '"key_file":"rsa_private_$1.pem"'
    $content = $content -replace '"cert_file":"[^A-Z0-9]+([A-Z0-9\-]+)\.pem"', '"cert_file":"rsa_cert_$1.pem"'
    $content = $content -replace '"ca_file":"[^"]+"', "`"ca_file`":`"$ca_file_name`""
    $content = $content -replace "`r`n", "`n"

    # The -Encoding utf8 causes Powershell to use Unix-type line endings and will not have a BOM
    # from Powershell version 6 onwards. For compatibility with older Powershell (shipped with
    # Windows 10), we use -Encoding ASCII to prevent the BOM from being inserted
    $content | Out-File -FilePath $NewFile -Encoding ascii -NoNewLine

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


