<#
.SYNOPSIS
Key and config rotator for EasyIO devices.

.DESCRIPTION
This script loops over a directory of backup files and puts modified backup files
into an output directory. TLS KEYS MUST BE GENERATED BEFORE RUNNING THIS SCRIPT.

.PARAMETER BackupProjectDirectory
The directory containing the EasyIO backup files. Each device's backups should be
in a subdirectory named after its IPv4 address.

.PARAMETER OutputProjectDirectory
The directory where the modified backup files will be placed, maintaining the
subdirectory structure of the input directory.

.PARAMETER KeysDirectory
The directory containing the TLS key files (rsa_private<devicename>.pem,
rsa_public<devicename>.pem, and CA File.pem).

.NOTES
Version: 0.2
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$BackupProjectDirectory,

    [Parameter(Mandatory=$true)]
    [string]$OutputProjectDirectory,

    [Parameter(Mandatory=$true)]
    [string]$KeysDirectory
)

# Check that the provided directory paths all exist
foreach ($dir in $BackupProjectDirectory, $OutputProjectDirectory, $KeysDirectory) {
    if (-not (Test-Path -Path $dir -PathType Container)) {
        Write-Error "$dir does not exist, quitting."
        exit 1
    }
}

function Identify-DeviceName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ExpandedArchivePath
    )
    $parameterFile = Join-Path $ExpandedArchivePath "cpt/plugins/DataServiceConfig/data_mapping.json"
    if (Test-Path $parameterFile) {
        try {
            $content = Get-Content -Path $parameterFile -Raw
            $match = $content | Select-String -Pattern '"device_id":"([^"]+)"' | Select-Object -First 1
            if ($match) {
                return $match.Matches.Groups[1].Value
            } else {
                Write-Warning "Could not find device_id in $parameterFile"
                return $null
            }
        } catch {
            Write-Error "Error reading or parsing $parameterFile: $($_.Exception.Message)"
            return $null
        }
    } else {
        Write-Warning "Parameter file not found: $parameterFile"
        return $null
    }
}

function Update-CloudSettings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ExpandedBackupRoot,
        [Parameter(Mandatory=$true)]
        [string]$DeviceName
    )
    $configurationPath = Join-Path $ExpandedBackupRoot "cpt/plugins/DataServiceConfig"
    $mappingFile = Join-Path $configurationPath "data_mapping.json"
    $tempFile = Join-Path $configurationPath "data_mapping.old.json"
    $sedSubstitutionScript = @(
        's/"essential-keep-197822"/"bos-platform-prod"/g',
        's/"mqtt.googleapis.com"/"mqtt.bos.goog"/g',
        "s/\"rsa_private[A-Z0-9]*\\.pem\"/\"rsa_private$DeviceName.pem\"/g",
        "s/\"rsa_public[A-Z0-9]*\\.pem\"/\"rsa_public$DeviceName.pem\"/g"
    ) -join ';'

    try {
        Move-Item -Path $mappingFile -Destination $tempFile -Force
        (Get-Content -Path $tempFile -Raw) | ForEach-Object {
            $sedSubstitutionScript.Split(';') | ForEach-Object {
                $pattern, $replacement = $_.Substring(2).Split('/')
                $_ -replace $pattern, $replacement
            }
        } | Set-Content -Path $mappingFile
        Remove-Item -Path $tempFile -Force
        return $true
    } catch {
        Write-Error "Error updating cloud settings in $mappingFile: $($_.Exception.Message)"
        return $false
    }
}

function Update-Keys {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ExpandedBackupRoot,
        [Parameter(Mandatory=$true)]
        [string]$DeviceName
    )
    $keysPath = Join-Path $ExpandedBackupRoot "cpt/plugins/DataServiceConfig/uploads/certs"
    $privateKeyFile = "rsa_private$DeviceName.pem"
    $publicKeyFile = "rsa_public$DeviceName.pem"
    $caFile = "CA File.pem"

    $sourcePrivateKey = Join-Path $KeysDirectory $privateKeyFile
    $sourcePublicKey = Join-Path $KeysDirectory $publicKeyFile
    $sourceCaFile = Join-Path $KeysDirectory $caFile

    $destinationPrivateKey = Join-Path $keysPath $privateKeyFile
    $destinationPublicKey = Join-Path $keysPath $publicKeyFile
    $destinationCaFile = Join-Path $keysPath $caFile

    if (Test-Path $keysPath) {
        Get-ChildItem -Path $keysPath | Remove-Item -Force
    } else {
        New-Item -Path $keysPath -ItemType Directory -Force | Out-Null
    }

    $copySuccess = $true
    if (-not (Copy-Item -Path $sourcePrivateKey -Destination $destinationPrivateKey -Force -ErrorAction SilentlyContinue)) {
        Write-Error "Failed to copy private key: $sourcePrivateKey to $destinationPrivateKey"
        $copySuccess = $false
    }
    if (-not (Copy-Item -Path $sourcePublicKey -Destination $destinationPublicKey -Force -ErrorAction SilentlyContinue)) {
        Write-Error "Failed to copy public key: $sourcePublicKey to $destinationPublicKey"
        $copySuccess = $false
    }
    if (-not (Copy-Item -Path $sourceCaFile -Destination $destinationCaFile -Force -ErrorAction SilentlyContinue)) {
        Write-Error "Failed to copy CA file: $sourceCaFile to $destinationCaFile"
        $copySuccess = $false
    }

    return $copySuccess
}

Write-Host "Processing EasyIO backup files in $BackupProjectDirectory..."

# Loop through all the device directories
Get-ChildItem -Path $BackupProjectDirectory -Directory | ForEach-Object {
    $deviceDirectoryName = $_.BaseName
    # Check if the directory name looks like an IPv4 address
    if ($deviceDirectoryName -match '^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$') {
        $backupFiles = Get-ChildItem -Path (Join-Path $BackupProjectDirectory $deviceDirectoryName) -Filter *.tgz | Sort-Object LastWriteTime -Descending
        $latestBackup = $backupFiles | Select-Object -First 1

        if ($latestBackup) {
            $outputDeviceDirectory = Join-Path $OutputProjectDirectory $deviceDirectoryName
            if (-not (Test-Path -Path $outputDeviceDirectory -PathType Container)) {
                try {
                    New-Item -Path $outputDeviceDirectory -ItemType Directory -Force | Out-Null
                } catch {
                    Write-Error "Failed to create directory: $outputDeviceDirectory - $($_.Exception.Message)"
                    continue
                }
            }

            $expandedOutputDirectory = Join-Path $outputDeviceDirectory "expanded_backup_$($latestBackup.BaseName)"
            try {
                Expand-Archive -Path $latestBackup.FullName -DestinationPath $expandedOutputDirectory -Force
            } catch {
                Write-Error "Error expanding archive $($latestBackup.FullName): $($_.Exception.Message)"
                continue
            }

            # Find the root directory of the expanded backup
            $expandedRoot = Get-ChildItem -Path $expandedOutputDirectory -Directory | Select-Object -First 1

            if ($expandedRoot) {
                $deviceName = Identify-DeviceName -ExpandedArchivePath $expandedRoot.FullName
                if ($deviceName) {
                    if (Update-CloudSettings -ExpandedBackupRoot $expandedRoot.FullName -DeviceName $deviceName) {
                        if (Update-Keys -ExpandedBackupRoot $expandedRoot.FullName -DeviceName $deviceName) {
                            $outputTarFileName = "$($latestBackup.BaseName)_updated.tgz"
                            $outputTarFullPath = Join-Path $outputDeviceDirectory $outputTarFileName
                            try {
                                Compress-Archive -Path $expandedRoot.FullName -DestinationPath $outputTarFullPath -CompressionLevel Optimal -Force
                                Remove-Item -Path $expandedRoot.FullName -Recurse -Force
                                Write-Host "$($latestBackup.FullName) -> $outputTarFullPath"
                            } catch {
                                Write-Error "Error creating output archive $outputTarFullPath: $($_.Exception.Message)"
                            }
                        } else {
                            Write-Error "Failed to update keys for $deviceDirectoryName."
                            Remove-Item -Path $expandedRoot.FullName -Recurse -Force
                        }
                    } else {
                        Write-Error "Failed to update cloud settings for $deviceDirectoryName."
                        Remove-Item -Path $expandedRoot.FullName -Recurse -Force
                    }
                } else {
                    Write-Error "Could not identify device name in backup for $deviceDirectoryName."
                    Remove-Item -Path $expandedRoot.FullName -Recurse -Force
                }
            } else {
                Write-Warning "Could not find the expanded root directory for $($latestBackup.FullName)."
            }
        } else {
            Write-Warning "No backup file found for $($_.FullName), skipping!"
        }
    } else {
        Write-Warning "Directory $($_.FullName) does not match the expected IPv4 format, skipping!"
    }
}

Write-Host "Finished."


