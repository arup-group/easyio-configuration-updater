# Key and config rotator for EasyIO devices
# TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT

param (
    [string]$BackupDirectory,
    [string]$OutputDirectory,
    [string]$KeySourceDirectory
)

# Check that required arguments are provided
if (-not $BackupDirectory -or -not $OutputDirectory -or -not $KeySourceDirectory) {
    Write-Host "Usage: script.ps1 <backup_project_directory> <output_project_directory> <keys_directory>"
    exit 1
}

# Verify provided directories exist
foreach ($dir in @($BackupDirectory, $OutputDirectory, $KeySourceDirectory)) {
    if (-not (Test-Path $dir -PathType Container)) {
        Write-Host "$dir does not exist, quitting."
        exit 1
    }
}

function Identify-DeviceName {
    param ($ExpandedArchivePath)
    $ParameterFile = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\data_mapping.json"
    $DeviceName = (Select-String -Path $ParameterFile -Pattern '"device_id":"[^"]+"' | Select-Object -First 1).Line -replace '".*":"(.*?)"', '$1'
    return $DeviceName
}

function Update-CloudSettings {
    param ($ExpandedArchivePath, $DeviceName)
    $ConfigurationPath = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig"
    $Substitutions = @{
        '"essential-keep-197822"' = '"bos-platform-prod"'
        '"mqtt.googleapis.com"' = '"mqtt.bos.goog"'
        '"rsa_private[A-Z0-9]*\.pem"' = "`"rsa_private$DeviceName.pem`""
        '"rsa_public[A-Z0-9]*\.pem"' = "`"rsa_public$DeviceName.pem`""
    }
    
    $ConfigFile = "$ConfigurationPath\data_mapping.json"
    $OldConfigFile = "$ConfigurationPath\data_mapping.old.json"
    Copy-Item -Path $ConfigFile -Destination $OldConfigFile
    (Get-Content $OldConfigFile) | ForEach-Object {
        $Line = $_
        foreach ($key in $Substitutions.Keys) {
            $Line = $Line -replace $key, $Substitutions[$key]
        }
        $Line
    } | Set-Content $ConfigFile

    Remove-Item $OldConfigFile
}

function Update-Keys {
    param ($ExpandedArchivePath, $DeviceName)
    $KeysPath = "$ExpandedArchivePath\cpt\plugins\DataServiceConfig\uploads\certs"
    $PrivateKey = "rsa_private$DeviceName.pem"
    $PublicKey = "rsa_public$DeviceName.pem"
    $CAFile = "CA File.pem"

    # Delete old keys
    if (Test-Path $KeysPath) {
        Remove-Item "$KeysPath\*" -Force
    }

    # Copy new keys
    Copy-Item "$KeySourceDirectory\$PrivateKey" "$KeysPath\$PrivateKey"
    Copy-Item "$KeySourceDirectory\$PublicKey" "$KeysPath\$PublicKey"
    Copy-Item "$KeySourceDirectory\$CAFile" "$KeysPath\$CAFile"
}

Write-Host "Processing EasyIO backup files in $BackupDirectory..."

foreach ($DeviceDirectory in Get-ChildItem $BackupDirectory | Where-Object { $_.PSIsContainer -and $_.Name -match '^\d+\.\d+\.\d+\.\d+$' }) {
    $LatestBackup = Get-ChildItem "$BackupDirectory\$($DeviceDirectory.Name)\*.tgz" | Sort-Object -Descending | Select-Object -First 1

    if ($LatestBackup -and $LatestBackup.PSIsContainer -eq $false) {
        $OutputDeviceDir = "$OutputDirectory\$($DeviceDirectory.Name)"
        if (!(Test-Path $OutputDeviceDir)) {
            New-Item -Path $OutputDeviceDir -ItemType Directory | Out-Null
        }

        # Expand backup
        tar -xzf $LatestBackup.FullName -C $OutputDeviceDir

        # Get expanded backup root directory
        $ExpandedRootDir = (Get-ChildItem $OutputDeviceDir | Where-Object { $_.PSIsContainer })[0].Name

        # Update settings and keys
        $DeviceName = Identify-DeviceName "$OutputDeviceDir\$ExpandedRootDir"
        if ($DeviceName) {
            Update-CloudSettings "$OutputDeviceDir\$ExpandedRootDir" $DeviceName
            Update-Keys "$OutputDeviceDir\$ExpandedRootDir" $DeviceName
        }

        # Compress updated backup
        $UpdatedBackupName = "$($LatestBackup.BaseName)_updated.tgz"
        tar -cz -C "$OutputDeviceDir" -f "$OutputDeviceDir\$UpdatedBackupName" "$ExpandedRootDir" 

        # Cleanup
        Remove-Item "$OutputDeviceDir\$ExpandedRootDir" -Recurse
        Write-Host "$BackupDirectory\$(LatestBackup.BaseName)  ->  $OutputDeviceDir\$UpdatedBackupName"
    } else {
        Write-Warning "No backup file found for $($DeviceDirectory.Name), skipping!"
    }
}

Write-Host "Finished."



