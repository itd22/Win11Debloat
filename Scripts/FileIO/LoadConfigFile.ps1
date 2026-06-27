# Loads a Win11Debloat config file (.json, .yaml or .yml) and returns the parsed object.
# Dispatches to the JSON or YAML parser based on file extension, but both paths return
# the same PSCustomObject shape, so callers don't need to know which format was used.
# Returns $null if the file doesn't exist or if parsing fails.
function LoadConfigFile {
    param (
        [string]$filePath,
        [string]$expectedVersion = $null,
        [switch]$optionalFile
    )

    if (-not (Test-Path $filePath)) {
        if (-not $optionalFile) {
            Write-Error "File not found: $filePath"
        }
        return $null
    }

    $extension = [System.IO.Path]::GetExtension($filePath).ToLowerInvariant()

    try {
        if ($extension -eq '.yaml' -or $extension -eq '.yml') {
            $yamlText = Get-Content -Path $filePath -Raw
            $parsed = ConvertFrom-ConfigYaml -YamlText $yamlText
        }
        else {
            $parsed = Get-Content -Path $filePath -Raw | ConvertFrom-Json
        }

        if ($expectedVersion -and $parsed.Version -and $parsed.Version -ne $expectedVersion) {
            Write-Error "$(Split-Path $filePath -Leaf) version mismatch (expected $expectedVersion, found $($parsed.Version))"
            return $null
        }

        return $parsed
    }
    catch {
        Write-Error "Failed to parse config file: $filePath"
        return $null
    }
}
