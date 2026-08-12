[CmdletBinding()]
param(
    [Parameter()]
    [string] $ProjectRoot,

    [Parameter()]
    [string] $OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    $ProjectRoot = $scriptDirectory
}
if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path (Split-Path -Parent $scriptDirectory) 'pets'
}

$projectPath = (Resolve-Path -LiteralPath $ProjectRoot).Path
$outputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputDirectory)
$outputPath = [System.IO.Path]::GetFullPath($outputPath)

$pathComparison = [System.StringComparison]::OrdinalIgnoreCase
if ($outputPath.Equals($projectPath, $pathComparison)) {
    throw "OutputDirectory cannot be the same directory as ProjectRoot: $outputPath"
}

$pets = @(
    Get-ChildItem -LiteralPath $projectPath -Directory |
        Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'package') -PathType Container } |
        Sort-Object Name
)

if ($pets.Count -eq 0) {
    throw "No pet package directories were found under: $projectPath"
}

New-Item -ItemType Directory -Path $outputPath -Force | Out-Null

foreach ($pet in $pets) {
    $source = Join-Path $pet.FullName 'package'
    $destination = Join-Path $outputPath $pet.Name
    $token = [System.Guid]::NewGuid().ToString('N')
    $staging = Join-Path $outputPath ('.{0}.staging.{1}' -f $pet.Name, $token)
    $backup = Join-Path $outputPath ('.{0}.backup.{1}' -f $pet.Name, $token)

    try {
        New-Item -ItemType Directory -Path $staging | Out-Null
        Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
            Copy-Item -LiteralPath $_.FullName -Destination $staging -Recurse -Force
        }

        if (Test-Path -LiteralPath $destination) {
            Move-Item -LiteralPath $destination -Destination $backup
        }

        try {
            Move-Item -LiteralPath $staging -Destination $destination
        }
        catch {
            if (Test-Path -LiteralPath $backup) {
                Move-Item -LiteralPath $backup -Destination $destination
            }
            throw
        }

        if (Test-Path -LiteralPath $backup) {
            Remove-Item -LiteralPath $backup -Recurse -Force
        }

        Write-Host ('Packed {0} -> {1}' -f $pet.Name, $destination)
    }
    finally {
        if (Test-Path -LiteralPath $staging) {
            Remove-Item -LiteralPath $staging -Recurse -Force
        }
    }
}

Write-Host ('Done. Packed {0} pet(s) into {1}' -f $pets.Count, $outputPath)
