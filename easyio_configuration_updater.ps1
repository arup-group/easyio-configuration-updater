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


# Function to identify the device names
function Identify-DeviceNames {
    param (
        [string]$ExpandedArchivePath
    )
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"
    $AllDeviceNames = Select-String -Path $ParameterFile -Pattern '"device_id":"([^"]+)"' -AllMatches | `
        % {$_.matches.groups | Where-Object {$_.Name -eq 1}} | % {$_.Value} 
    return $AllDeviceNames
}


function Update-CloudSettings {
    param (
        [string]$ExpandedBackupRoot
    )
    # This function also uses global variables project_id, registry_id, region_id, mqtt_host_id, events_interval

    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    # Read JSON file contents
    $content = Get-Content $OldFile -Raw

    # Apply substitutions
    $content = $content -creplace '"project_id":"[^"]+"', "`"project_id`":`"$project_id`""
    $content = $content -creplace '"registry_id":"[^"]+"', "`"registry_id`":`"$registry_id`""
    $content = $content -creplace '"region":"[^"]+"', "`"region`":`"$region_id`""
    $content = $content -creplace '"mqtt_host":"[^"]+"', "`"mqtt_host`":`"$mqtt_host_id`""
    $content = $content -creplace '"events_interval":[0-9]+', "`"events_interval`":$events_interval"
    $content = $content -creplace "`r`n", "`n"

    # The -Encoding utf8 causes Powershell to use Unix-type line endings and will not have a BOM
    # from Powershell version 6 onwards. For compatibility with older Powershell (shipped with
    # Windows 10), we use -Encoding ASCII to prevent the BOM from being inserted
    $content | Out-File -FilePath $NewFile -Encoding ascii -NoNewLine

    # In Powershell, we can't rename a file onto a destination that already exists, so we use 'Move-Item'
    # instead    
    Move-Item -Path $NewFile -Destination $OldFile -Force
}

function Update-Keys {
    param (
        [string]$ExpandedBackupRoot,
	[string]$KeysDirectory,
	[string]$ca_file_name,
        [string]$AllDeviceNames
    )

    $KeysPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig\uploads\certs"
    $ConfigurationPath = "$ExpandedBackupRoot\cpt\plugins\DataServiceConfig"
    $OldFile = "$ConfigurationPath\data_mapping.json"
    $NewFile = "$ConfigurationPath\data_mapping.updated.json"

    # Read JSON file contents
    $content = Get-Content $OldFile -Raw

    # Apply substitutions
    $content = $content -creplace '"key_file":"[^A-Z0-9]+([A-Z]+)-?([0-9]+)\.pem"', '"key_file":"rsa_private_$1-$2.pem"'
    $content = $content -creplace '"cert_file":"[^A-Z0-9]+([A-Z]+)-?([0-9]+)\.pem"', '"cert_file":"rsa_cert_$1-$2.pem"'
    $content = $content -creplace '"ca_file":"[^"]+"', "`"ca_file`":`"$ca_file_name`""
    $content = $content -creplace "`r`n", "`n"

    $content | Out-File -FilePath $NewFile -Encoding ascii -NoNewLine
    Move-Item -Path $NewFile -Destination $OldFile -Force

    # Clear old keys
    Remove-Item "$KeysPath\*" -Force -ErrorAction SilentlyContinue

    # Copy new CA file
    Copy-Item "$KeysDirectory\$ca_file_name" "$KeysPath\$ca_file_name"

    ForEach ($DeviceName in $AllDeviceNames.split()) {
        $PrivateKeyFile = "rsa_private_$DeviceName.pem"
        $CertFile = "rsa_cert_$DeviceName.pem"
        # Copy new ones
        Copy-Item "$KeysDirectory\$DeviceName\rsa_private.pem" "$KeysPath\$PrivateKeyFile"
        Copy-Item "$KeysDirectory\$DeviceName\rsa_cert.pem" "$KeysPath\$CertFile"
    }

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


function Get-Parameters {
     param (
        [string]$ParameterFile
    )

    if (-not $ParameterFile) {
        Write-Host "Usage: $($MyInvocation.MyCommand.Name) [parameter_file]"
        exit 1
    }

    # Read parameter file
    $parameter_file_contents = Get-Content "$ParameterFile"
    if (-not $?) {
	Write-Host "Failed to load $ParameterFile"
	exit 1
    }

    # Check that all required parameters are provided
    foreach ($parameter_name in "BackupProjectDirectory", "OutputProjectDirectory", "KeysDirectory", `
                 "project_id", "registry_id", "region_id", "mqtt_host_id", "ca_file_name", "events_interval") {
	$parameter_value = $parameter_file_contents | Select-String -Pattern "^$parameter_name\s*=\s*`"([^`"]+)`"" | % {$_.matches.Groups[1].Value}

	# push the setting into global namespace
        Set-Variable -Name global:$parameter_name -Value $parameter_value
        if (-not $parameter_value -or $parameter_value -eq "") {
            Write-Host "Parameter is not defined: $parameter_name"
            if (-not ($parameter_name -eq "KeysDirectory")) {
                Write-Host "Quitting."
                exit 1
            }
            else {
                Write-Host "Note: keys directory not provided, existing keys in backups will be retained."
		$global:KeysDirectory = "" 
            }
        }
    }

    # Check that the provided directories exist on valid paths
    foreach ($dir in $global:BackupProjectDirectory, $global:OutputProjectDirectory, $global:KeysDirectory) {
        if ($dir -and -not (Test-Path -Path $dir -PathType Container)) {
            Write-Host "$dir does not exist, quitting." | Write-Error
            exit 1
        }
    }

    Write-Host "Directory parameters:"
    Write-Host "  backup project directory:     $global:BackupProjectDirectory"
    Write-Host "  output project directory:     $global:OutputProjectDirectory"
    Write-Host "  keys directory:               $global:KeysDirectory"
    Write-Host "Substitution parameters:"
    Write-Host "  project_id:                   $global:project_id"
    Write-Host "  registry_id:                  $global:registry_id"
    Write-Host "  region_id:                    $global:region_id"
    Write-Host "  mqtt_host:                    $global:mqtt_host_id"
    Write-Host "  ca_file:                      $global:ca_file_name"
    Write-Host "  events_interval:              $global:events_interval"
}


#
# Script processing starts here
# 

# Read configuration parameters from file
Get-Parameters $ParameterFile

Write-Host "Processing EasyIO backup files in $BackupProjectDirectory..."

foreach ($DeviceDirectory in Get-ChildItem -Path $BackupProjectDirectory -Directory) {
    if ($DeviceDirectory.Name -match '^\d+\.\d+\.\d+\.\d+$') {

        # Save names of input and output directories, and backup file name, as strings
        $InputDeviceDirectory = "$BackupProjectDirectory\$($DeviceDirectory.Name)"
        $OutputDeviceDirectory = "$OutputProjectDirectory\$($DeviceDirectory.Name)"
        $LatestBackup = (Get-ChildItem "$BackupProjectDirectory\$($DeviceDirectory.Name)\*.tgz" `
	    | Sort-Object Name | Select-Object -Last 1).Name
        
        # If we've got a valid archive file, then process it
        if (Test-Path -Path "$InputDeviceDirectory\$LatestBackup" -PathType Leaf) {

            # Create an output folder for the device, if it doesn't exist already
            if (-not (Test-Path -Path $OutputDeviceDirectory)) {
                New-Item -ItemType Directory -Path $OutputDeviceDirectory | Out-Null
            }

            # Expand the archive into the output project folder
            tar -xz -C "$OutputDeviceDirectory" -f "$InputDeviceDirectory\$LatestBackup"

            # Get the root directory
            $ExpandedRootDir = (Get-ChildItem -Path $OutputDeviceDirectory -Directory | `
	        Select-Object -First 1).Name

            # Make the changes and then re-archive the directory with a new name
            if ($ExpandedRootDir) {
                $AllDeviceNames = Identify-DeviceNames "$OutputDeviceDirectory\$ExpandedRootDir"
                Update-CloudSettings "$OutputDeviceDirectory\$ExpandedRootDir"

                if ($KeysDirectory) {
                    Update-Keys "$OutputDeviceDirectory\$ExpandedRootDir" $KeysDirectory $ca_file_name $AllDeviceNames
                }
                Update-TimeSettings "$OutputDeviceDirectory\$ExpandedRootDir"

                Move-Item -Path "$OutputDeviceDirectory\$ExpandedRootDir" `
		    -Destination "$OutputDeviceDirectory\updated_backup" -Force
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


