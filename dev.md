# Design: Save/Load chosen checkboxes to win11-debloat.yaml

## Existing code to reuse

The project already has a working config export/import pipeline (JSON-based):

- `Config/LastUsedSettings.json` — auto-saved snapshot of last run's selections.
- `Config/DefaultSettings.json` — ships as the default preset, same schema.
- `Scripts/Helpers/ImportConfigToParams.ps1` — loads a config file into the script's `$Params` hashtable (used by CLI `-Config` and `-RunSavedSettings`).
- `Scripts/GUI/Show-ConfigWindow.ps1` — GUI picker for export/import, category selection.
- Shared `SaveToFile` helper (introduced in upstream PR #522) — writes current GUI selections to disk.

Schema (from `DefaultSettings.json`):
```json
{
  "Version": "1.0",
  "Settings": [
    { "Name": "DisableTelemetry", "Value": true },
    { "Name": "TaskbarAlignLeft", "Value": true }
  ]
}
```

This is checkbox-state-to-disk already solved for JSON. The task here is to add a parallel YAML path (`win11-debloat.yaml`) using the same `Name`/`Value` shape, not to redesign the GUI/CLI plumbing.

## Plan

1. **Add YAML (de)serialization helper**
   - New file: `Scripts/Helpers/Convert-Yaml.ps1` (or reuse `powershell-yaml` module if already a dependency; otherwise vendor a minimal YAML reader/writer since this project avoids external deps).
   - Two functions: `ConvertTo-Win11DebloatYaml [hashtable]$Settings` and `ConvertFrom-Win11DebloatYaml [string]$Path`.
   - Internally still produce/consume the same `Version` + `Settings[{Name,Value}]` shape — just serialized as YAML instead of JSON.

2. **Extend `SaveToFile` helper**
   - Add a `-Format Yaml|Json` switch (default stays `Json` for backward compatibility).
   - When `Yaml`, write to `win11-debloat.yaml` instead of `*.json`, using the new helper.

3. **Extend `ImportConfigToParams.ps1`**
   - Detect format by file extension (`.yaml`/`.yml` vs `.json`).
   - Dispatch to `ConvertFrom-Win11DebloatYaml` or the existing JSON parsing path before populating `$Params`.

4. **GUI (`Show-ConfigWindow.ps1`)**
   - Add a format toggle (or just file-extension-based detection in the save/open dialog filter: `*.yaml;*.json`).
   - No change to checkbox-state collection logic — it already walks the same settings list; only the serialization target changes.

5. **CLI**
   - `-Config <path>` already accepts a file path; just needs the extension-based dispatch from step 3. No new parameter needed.

## File location

- Default save target: `Config/win11-debloat.yaml` (sits alongside `LastUsedSettings.json`).
- User-exported configs: wherever the user picks via the GUI save dialog, defaulting to `win11-debloat.yaml`.

## Out of scope / non-goals

- Not replacing JSON — both formats coexist; YAML is additive.
- Not changing `Features.json` or `Apps.json` (those are static metadata, not user selections).
