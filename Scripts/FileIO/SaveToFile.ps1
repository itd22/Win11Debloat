# Saves configuration to a file as JSON or YAML, based on the FilePath extension
# (.yaml/.yml -> YAML, anything else -> JSON, matching prior behaviour).
# Returns $true on success, $false on failure.
function SaveToFile {
    param (
        [Parameter(Mandatory=$true)]
        [hashtable]$Config,

        [Parameter(Mandatory=$true)]
        [string]$FilePath,

        [Parameter(Mandatory=$false)]
        [int]$MaxDepth = 10
    )

    try {
        $extension = [System.IO.Path]::GetExtension($FilePath).ToLowerInvariant()

        if ($extension -eq '.yaml' -or $extension -eq '.yml') {
            ConvertTo-ConfigYaml -Config $Config | Set-Content -Path $FilePath -Encoding UTF8
        }
        else {
            $Config | ConvertTo-Json -Depth $MaxDepth | Set-Content -Path $FilePath -Encoding UTF8
        }
        return $true
    }
    catch {
        return $false
    }
}
