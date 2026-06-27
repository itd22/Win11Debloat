# Minimal, dependency-free YAML support for Win11Debloat configuration files.
# Only needs to round-trip the specific config shape used by SaveToFile / LoadJsonFile:
#   Version: "1.0"
#   Apps:
#     - AppId1
#     - AppId2
#   Tweaks:
#     - Name: FeatureId
#       Value: true
#   Deployment:
#     - Name: SettingName
#       Value: <bool|int|string>
#
# This is intentionally NOT a general-purpose YAML parser. It supports just enough
# of the YAML 1.1 subset that ConvertTo-ConfigYaml emits, so Win11Debloat does not
# need to take a dependency on an external module (e.g. powershell-yaml).

# Converts a config hashtable (same shape used with SaveToFile/ConvertTo-Json) into
# a YAML string.
function ConvertTo-ConfigYaml {
    param (
        [Parameter(Mandatory = $true)]
        [hashtable]$Config
    )

    function YamlScalar {
        param ($Value)

        if ($null -eq $Value) { return 'null' }
        if ($Value -is [bool]) { return $Value.ToString().ToLower() }
        if ($Value -is [int] -or $Value -is [long] -or $Value -is [double]) { return "$Value" }

        $text = "$Value"
        if ($text -eq '') { return "''" }
        # Quote if it could be misread as a different type, or contains YAML-significant characters
        if ($text -match '^(true|false|null|~|[-+]?[0-9]+(\.[0-9]+)?)$' -or $text -match '[:#\[\]\{\}\x27\"]' -or $text -match '^\s|\s$') {
            return "'" + ($text -replace "'", "''") + "'"
        }
        return $text
    }

    $lines = @()
    $lines += "Version: $(YamlScalar $Config.Version)"

    if ($Config.ContainsKey('Apps')) {
        $apps = @($Config.Apps)
        if ($apps.Count -eq 0) {
            $lines += 'Apps: []'
        }
        else {
            $lines += 'Apps:'
            foreach ($app in $apps) {
                $lines += "  - $(YamlScalar $app)"
            }
        }
    }

    if ($Config.ContainsKey('Tweaks')) {
        $tweaks = @($Config.Tweaks)
        if ($tweaks.Count -eq 0) {
            $lines += 'Tweaks: []'
        }
        else {
            $lines += 'Tweaks:'
            foreach ($tweak in $tweaks) {
                $lines += "  - Name: $(YamlScalar $tweak.Name)"
                $lines += "    Value: $(YamlScalar $tweak.Value)"
            }
        }
    }

    if ($Config.ContainsKey('Deployment')) {
        $deployment = @($Config.Deployment)
        if ($deployment.Count -eq 0) {
            $lines += 'Deployment: []'
        }
        else {
            $lines += 'Deployment:'
            foreach ($setting in $deployment) {
                $lines += "  - Name: $(YamlScalar $setting.Name)"
                $lines += "    Value: $(YamlScalar $setting.Value)"
            }
        }
    }

    if ($Config.ContainsKey('Settings')) {
        $settings = @($Config.Settings)
        if ($settings.Count -eq 0) {
            $lines += 'Settings: []'
        }
        else {
            $lines += 'Settings:'
            foreach ($setting in $settings) {
                $lines += "  - Name: $(YamlScalar $setting.Name)"
                $lines += "    Value: $(YamlScalar $setting.Value)"
            }
        }
    }

    return ($lines -join "`n") + "`n"
}

# Parses a YAML string produced by ConvertTo-ConfigYaml back into a PSCustomObject
# with the same shape as ConvertFrom-Json would produce, so existing code that reads
# $config.Version / $config.Apps / $config.Tweaks / $config.Deployment / $config.Settings
# (and .Name/.Value on Tweaks/Deployment/Settings entries) keeps working unchanged.
function ConvertFrom-ConfigYaml {
    param (
        [Parameter(Mandatory = $true)]
        [string]$YamlText
    )

    function UnquoteScalar {
        param ([string]$Token)

        $Token = $Token.Trim()
        if ($Token -eq '' -or $Token -eq '~' -or $Token -eq 'null') { return $null }
        if ($Token -eq 'true') { return $true }
        if ($Token -eq 'false') { return $false }

        if ($Token.Length -ge 2 -and $Token.StartsWith("'") -and $Token.EndsWith("'")) {
            return $Token.Substring(1, $Token.Length - 2) -replace "''", "'"
        }
        if ($Token.Length -ge 2 -and $Token.StartsWith('"') -and $Token.EndsWith('"')) {
            return $Token.Substring(1, $Token.Length - 2)
        }
        if ($Token -match '^[-+]?[0-9]+$') { return [int]$Token }
        if ($Token -match '^[-+]?[0-9]+\.[0-9]+$') { return [double]$Token }

        return $Token
    }

    $result = [ordered]@{}
    $rawLines = $YamlText -split "`r?`n" | Where-Object { $_.Trim() -ne '' -and -not $_.Trim().StartsWith('#') }

    $currentKey = $null
    $currentList = $null
    $pendingItem = $null

    function FlushPendingItem {
        if ($null -ne $pendingItem -and $null -ne $currentList) {
            $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
        }
        $script:pendingItem = $null
    }

    foreach ($line in $rawLines) {
        if ($line -match '^([A-Za-z0-9_]+):\s*(\[\])?\s*$' -and -not $line.StartsWith(' ')) {
            # New top-level key: e.g. "Apps:" or "Tweaks:" or "Settings: []"
            if ($null -ne $pendingItem -and $null -ne $currentList) {
                $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
                $pendingItem = $null
            }
            $currentKey = $Matches[1]
            $currentList = New-Object System.Collections.Generic.List[object]
            $result[$currentKey] = $currentList
            continue
        }

        if ($line -match '^([A-Za-z0-9_]+):\s*(.*)$' -and -not $line.StartsWith(' ')) {
            # Top-level scalar: e.g. "Version: '1.0'"
            if ($null -ne $pendingItem -and $null -ne $currentList) {
                $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
                $pendingItem = $null
            }
            $result[$Matches[1]] = UnquoteScalar $Matches[2]
            $currentKey = $null
            $currentList = $null
            continue
        }

        if ($line -match '^\s\s-\s+([A-Za-z0-9_]+):\s*(.*)$') {
            # List item start (covers both scalar list items like "  - AppId" via Name-less form,
            # and the first field of an object list item like "  - Name: Foo")
            if ($Matches[1] -eq 'Name' -and $null -ne $currentList) {
                if ($null -ne $pendingItem) {
                    $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
                }
                $pendingItem = [ordered]@{ Name = (UnquoteScalar $Matches[2]) }
                continue
            }
        }

        if ($line -match '^\s\s-\s+(.*)$' -and $null -ne $currentList) {
            # Plain scalar list item, e.g. apps: "  - SomeApp"
            if ($null -ne $pendingItem) {
                $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
                $pendingItem = $null
            }
            $currentList.Add((UnquoteScalar $Matches[1])) | Out-Null
            continue
        }

        if ($line -match '^\s\s\s\s([A-Za-z0-9_]+):\s*(.*)$' -and $null -ne $pendingItem) {
            # Continuation field of an object list item, e.g. "    Value: true"
            $pendingItem[$Matches[1]] = UnquoteScalar $Matches[2]
            continue
        }
    }

    if ($null -ne $pendingItem -and $null -ne $currentList) {
        $currentList.Add([PSCustomObject]$pendingItem) | Out-Null
    }

    # Convert ordered hashtable -> PSCustomObject, and inner Lists -> arrays, to mirror
    # the object shape ConvertFrom-Json would normally return.
    $obj = [PSCustomObject]@{}
    foreach ($key in $result.Keys) {
        $value = $result[$key]
        if ($value -is [System.Collections.Generic.List[object]]) {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue @($value.ToArray())
        }
        else {
            $obj | Add-Member -NotePropertyName $key -NotePropertyValue $value
        }
    }

    return $obj
}
