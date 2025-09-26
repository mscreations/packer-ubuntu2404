param (
    [Parameter()]
    [string]$Version = "24.04",     # Will build latest by default. Can specify specific version with this argument.

    [Parameter()]
    [string]$packerFile = ".\ubuntu.pkr.hcl"
)

# Parses the packer manifest for the virtual machine name
function Get-PackerVarName {
    param (
        [string]$PackerFile
    )

    if (-Not (Test-Path $PackerFile)) {
        throw "Packer file $PackerFile not found."
    }

    # Run packer inspect -machine-readable
    $output = & packer inspect -machine-readable $PackerFile 2>&1

    if ($LASTEXITCODE -ne 0) {
        throw "packer inspect failed: $output"
    }

    # Look for a line with var.name:
    foreach ($line in $output) {
        if ($line -match 'var\.name:\s*"([^"]+)"') {
            return $Matches[1]
        }
    }

    # Fallbacks if not found
    if ($env:NAME) {
        return $env:NAME
    }

    return Read-Host "Enter value for var.name"
}

# Checks if the VM already exists and if so, forcibly removes it.
function Remove-ExistingVM {
    param (
        [string]$VMName
    )

    try {
        $vm = Get-VM -Name $VMName -ErrorAction SilentlyContinue

        if (-not $vm) {
            Write-Host "No VM named '$VMName' exists. Nothing to remove."
            return
        }

        Write-Host "VM '$VMName' exists. State: $($vm.State)"

        if ($vm.State -eq 'Running') {
            Write-Host "Stopping VM '$VMName'..."
            Stop-VM -Name $VMName -Force -ErrorAction Stop
            # Wait for the VM to be off
            do {
                Start-Sleep -Seconds 2
                $vm = Get-VM -Name $VMName
            } while ($vm.State -eq 'Running')

            Write-Host "VM '$VMName' stopped."
        }

        Write-Host "Removing VM '$VMName'..."
        Remove-VM -Name $VMName -Force -ErrorAction Stop
        Write-Host "VM '$VMName' removed successfully."
    }
    catch {
        Write-Error "Error while handling VM '$VMName': $_"
        exit 1
    }
}

# Loads HCP Variables from .env file (authentication credentials)
function LoadHCPVariables {
    param (
        [string]$EnvFile = ".env",
        [switch]$Remove
    )

    if (-Not (Test-Path $EnvFile)) {
        Write-Error "The file $EnvFile was not found."
        exit 1
    }

    # Read each line of the .env file
    Get-Content $EnvFile | ForEach-Object {
        # Skip comments and empty lines
        if ($_ -match '^\s*#' -or [string]::IsNullOrWhiteSpace($_)) {
            return
        }

        # Split KEY=VALUE pairs
        $parts = $_ -split '=', 2
        if ($parts.Length -eq 2) {
            $key = $parts[0].Trim()

            if ($Remove) {
                Write-Host "Removing environment variable: $key"
                [System.Environment]::SetEnvironmentVariable($key, $null, "Process")
            }
            else {
                $value = $parts[1].Trim()
                Write-Host "Setting environment variable: $key"
                [System.Environment]::SetEnvironmentVariable($key, $value, "Process")
            }
        }
        else {
            Write-Warning "Skipping invalid line: $_"
        }
    }
}

function Get-UbuntuIsoInfo {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Version,
        [string]$Arch = "amd64",
        [string]$IsoType = "live-server"
    )

    # Base URL for requested release
    $baseUrl = "https://releases.ubuntu.com/$Version"
    $shaFileUrl = "$baseUrl/SHA256SUMS"

    # Check if SHA256SUMS exists
    try {
        Invoke-WebRequest -Uri $shaFileUrl -Method Head -ErrorAction Stop | Out-Null
    } catch {
        Write-Warning "Ubuntu version '$Version' not found at $baseUrl."
        Write-Host "Available versions:"

        # Scrape available versions from the main releases page
        $releasesPage = Invoke-WebRequest "https://releases.ubuntu.com/" -UseBasicParsing
        $availableVersions = ($releasesPage.Links | Where-Object { $_.href -match "^\d+\.\d+(\.\d+)?/$" }).href
        $availableVersions = $availableVersions | ForEach-Object { $_.TrimEnd('/') }

        Write-Host ($availableVersions -join ", ")
        exit 1
    }

    # Download SHA256SUMS
    $tmpShaFile = [System.IO.Path]::Combine($env:TEMP, "SHA256SUMS_$Version")
    Invoke-WebRequest -Uri $shaFileUrl -OutFile $tmpShaFile -UseBasicParsing

    # Pattern to match requested version (partial or full)
    $pattern = "ubuntu-$Version(?:\.\d+)?-$IsoType-$Arch\.iso"

    # Find all matching lines in SHA256SUMS
    $matching_lines = Select-String -Path $tmpShaFile -Pattern $pattern
    if (-not $matching_lines) {
        throw "No ISO found matching version '$Version'"
    }

    # Extract ISO filenames (second column in SHA256SUMS)
    $isoFiles = $matching_lines | ForEach-Object { ($_ -split "\s+")[1] }

    # Determine latest version
    $latestIso = $isoFiles | Sort-Object {
        if ($_ -match "ubuntu-(\d+\.\d+(?:\.\d+)?)-$IsoType-$Arch\.iso") { $Matches[1] } else { "0.0.0" }
    } -Descending | Select-Object -First 1

    # Extract corresponding checksum
    $pattern = [regex]::Escape($latestIso)

    $checksumLine = Select-String -Path $tmpShaFile -Pattern $pattern
    if (-not $checksumLine) {
        throw "Checksum not found for ISO '$latestIso'"
    }
    # $checksum = ($checksumLine.Line -split "\s+")[0]
    if ($checksumLine.Line -match "^(?<Checksum>[a-fA-F0-9]{64}) \*(?<Filename>.+\.iso)$") {
        $checksum = $Matches.Checksum
        $latestIso = $Matches.Filename
    } else {
        throw "Failed to parse checksum line: $($checksumLine.Line)"
    }


    # Return ISO info
    return @{
        IsoUrl   = "$baseUrl/$latestIso"
        IsoName  = $latestIso
        Checksum = $checksum
    }
}

$UbuntuVersion = Get-UbuntuIsoInfo -Version $Version
$isoUrls = @("iso/$($UbuntuVersion.IsoName)", "$($UbuntuVersion.IsoUrl)")

# Convert to JSON
$isoUrlsJson = $isoUrls | ConvertTo-Json -Compress

$vmName = Get-PackerVarName $packerFile
Write-Host "Resolved VM name: $vmName"

Remove-ExistingVM -VMName $vmName

LoadHCPVariables

Write-Host "Updating Packer plugins"
packer init -upgrade $packerFile

$buildDescription = "Generic Ubuntu Server $Version image for Hyper-V."

# Run packer build
Write-Host "Running: packer build .\ubuntu.pkr.hcl"
packer build `
    -timestamp-ui `
    -var "iso_urls=$isoUrlsJson" `
    -var "iso_checksum=$($UbuntuVersion.Checksum)" `
    -var "build_description=$buildDescription" `
    $packerFile

LoadHCPVariables -Remove