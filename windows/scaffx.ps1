param(
    [string]$cmd1,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$rest
)

$FILETEMPLATES = Join-Path $PSScriptRoot "templates/files"
$ARCHTEMPLATES = Join-Path $PSScriptRoot "templates/architectures"

# -- Parse flags and positional args from $rest -------------------------------

$flags      = $rest | Where-Object { $_ -like "--*" }
$positional = $rest | Where-Object { $_ -notlike "--*" }
$cmd2       = if ($positional.Count -gt 0) { $positional[0] } else { "" }

$filesOnly = $flags -contains "--files-only"
$dirsOnly  = $flags -contains "--dirs-only"
$clean     = $flags -contains "--clean"

if ($filesOnly -and $dirsOnly) {
    Write-Host ""
    Write-Host "  error  --files-only y --dirs-only no pueden usarse juntos" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# -- Command table ------------------------------------------------------------

$COMMANDS = @(
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx tree";          Desc = "muestra representacion visual de la arquitectura de archivos" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx tree <depth>";  Desc = "limita la profundidad del arbol (ej: scaffx tree 2)" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx snapshot";      Desc = "genera <raiz>.yaml con la estructura actual del folder" },
    [PSCustomObject]@{ Group = "flags";   Cmd = "  --files-only";       Desc = "incluye solo archivos (tree / snapshot)" },
    [PSCustomObject]@{ Group = "flags";   Cmd = "  --dirs-only";        Desc = "incluye solo directorios (tree / snapshot)" },
    [PSCustomObject]@{ Group = "flags";   Cmd = "  --clean";            Desc = "omite entradas segun .gitignore o scaffx.ignore (tree / snapshot)" }
)

# -- UI helpers ---------------------------------------------------------------

function Write-Header([string]$title) {
    Write-Host ""
    Write-Host "  $title" -ForegroundColor Cyan
    Write-Host "  $('-' * 40)" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-Row([string]$label, [string]$msg, [string]$status = "ok") {
    $icon  = switch ($status) { "ok" { "+" } "warn" { "warn" } "skip" { "-" } "none" { "." } default { " " } }
    $color = switch ($status) { "ok" { "Green" } "warn" { "Yellow" } default { "DarkGray" } }
    Write-Host ("  {0,-10}" -f $label) -ForegroundColor DarkGray -NoNewline
    Write-Host "$icon  " -ForegroundColor $color -NoNewline
    Write-Host $msg -ForegroundColor Gray
}

function Write-Fail([string]$msg) {
    Write-Host ""
    Write-Host "  error  $msg" -ForegroundColor Red
    Write-Host ""
}

# -- Guides ------------------------------------------------------------------

function Show-Help {
    Write-Header "scaffx"
    $groups = $COMMANDS | Select-Object -ExpandProperty Group -Unique
    foreach ($g in $groups) {
        Write-Host "  $g" -ForegroundColor DarkGray
        $COMMANDS | Where-Object { $_.Group -eq $g } | ForEach-Object {
            Write-Host ("  {0,-36}" -f $_.Cmd) -ForegroundColor Cyan -NoNewline
            Write-Host $_.Desc -ForegroundColor DarkGray
        }
        Write-Host ""
    }
}

# -- Helpers ------------------------------------------------------------------

function Confirm([string]$msg) {
    Write-Host ""
    Write-Row "" $msg "warn"
    $reply = Read-Host "  Desea continuar? [Y/n]"
    Write-Host ""
    return ($reply -match '^[Yy]')
}

function Get-Template([string]$file, [hashtable]$replacements) {
    $path = Join-Path $FILETEMPLATES $file
    if (-not (Test-Path $path)) {
        Write-Fail "template no encontrado: $file"
        return ""
    }
    $content = Get-Content $path -Raw
    foreach ($key in $replacements.Keys) {
        $content = $content -replace "{{${key}}}", $replacements[$key]
    }
    return $content
}

function Get-IgnorePatterns {
    $gitignore = Join-Path (Get-Location).Path ".gitignore"
    if (Test-Path $gitignore) {
        $source = $gitignore
    } else {
        $source = Join-Path $FILETEMPLATES "scaffx.ignore"
    }

    if (-not (Test-Path $source)) { return @() }

    $patterns = Get-Content $source | Where-Object {
        $_ -and $_ -notmatch '^\s*#'   # omite vacias y comentarios
    } | ForEach-Object { $_.Trim() }

    return $patterns
}

function Test-Ignored {
    param(
        [System.IO.FileSystemInfo]$item,
        [string[]]$patterns
    )

    if (-not $patterns -or $patterns.Count -eq 0) { return $false }

    $name     = $item.Name
    $fullPath = $item.FullName -replace '\\', '/'

    foreach ($pattern in $patterns) {
        $p = $pattern -replace '\\', '/'

        # Patron de directorio (termina en /)
        if ($p.EndsWith('/')) {
            if ($item.PSIsContainer) {
                $dirPattern = $p.TrimEnd('/')
                if ($name -like $dirPattern) { return $true }
            }
            continue
        }

        # Patron con slash interno => match sobre la ruta completa
        if ($p -match '/') {
            if ($fullPath -like "*/$p") { return $true }
            if ($fullPath -like "*/$p/*") { return $true }
        } else {
            # Sin slash => match solo sobre el nombre
            if ($name -like $p) { return $true }
        }
    }

    return $false
}

function Get-TreeLines {
    param(
        [string]$path,
        [string]$prefix = "",
        [int]$depth = 0,
        [int]$maxDepth = -1,
        [bool]$onlyFiles = $false,
        [bool]$onlyDirs  = $false,
        [string[]]$ignorePatterns = @()
    )

    if ($maxDepth -ge 0 -and $depth -ge $maxDepth) { return }

    $all = Get-ChildItem -LiteralPath $path | Sort-Object { $_.PSIsContainer -eq $false }, Name

    $visible = if ($onlyFiles) {
        $all | Where-Object { -not $_.PSIsContainer }
    } elseif ($onlyDirs) {
        $all | Where-Object { $_.PSIsContainer }
    } else {
        $all
    }

    if ($ignorePatterns.Count -gt 0) {
        $visible = $visible | Where-Object { -not (Test-Ignored -item $_ -patterns $ignorePatterns) }
    }

    for ($i = 0; $i -lt $visible.Count; $i++) {
        $item     = $visible[$i]
        $isLast   = ($i -eq $visible.Count - 1)
        $branch   = if ($isLast) { "└── " } else { "├── " }
        $childPfx = if ($isLast) { "    " } else { "│   " }

        if ($item.PSIsContainer) {
            Write-Host "$prefix$branch" -ForegroundColor DarkGray -NoNewline
            Write-Host $item.Name -ForegroundColor Cyan
            Get-TreeLines -path $item.FullName -prefix "$prefix$childPfx" -depth ($depth + 1) `
                          -maxDepth $maxDepth -onlyFiles $onlyFiles -onlyDirs $onlyDirs `
                          -ignorePatterns $ignorePatterns
        } else {
            Write-Host "$prefix$branch" -ForegroundColor DarkGray -NoNewline
            Write-Host $item.Name -ForegroundColor Gray
        }
    }
}

function Build-YamlLines {
    param(
        [string]$path,
        [int]$depth = 0,
        [int]$indentSize = 2,
        [bool]$onlyFiles = $false,
        [bool]$onlyDirs  = $false,
        [string[]]$ignorePatterns = @()
    )

    $lines  = [System.Collections.Generic.List[string]]::new()
    $indent = " " * ($depth * $indentSize)

    $all = Get-ChildItem -LiteralPath $path | Sort-Object { $_.PSIsContainer -eq $false }, Name

    $visible = if ($onlyFiles) {
        $all | Where-Object { -not $_.PSIsContainer }
    } elseif ($onlyDirs) {
        $all | Where-Object { $_.PSIsContainer }
    } else {
        $all
    }

    if ($ignorePatterns.Count -gt 0) {
        $visible = $visible | Where-Object { -not (Test-Ignored -item $_ -patterns $ignorePatterns) }
    }

    foreach ($item in $visible) {
        if ($item.PSIsContainer) {
            $lines.Add("${indent}- $($item.Name):")
            $children = Build-YamlLines -path $item.FullName -depth ($depth + 1) `
                                        -indentSize $indentSize -onlyFiles $onlyFiles -onlyDirs $onlyDirs `
                                        -ignorePatterns $ignorePatterns
            foreach ($child in $children) {
                $lines.Add($child)
            }
        } else {
            $lines.Add("${indent}- $($item.Name)")
        }
    }

    return $lines
}

# -- Commands -----------------------------------------------------------------

function Show-Tree {
    param([int]$maxDepth = -1)

    $filterLabel = if ($filesOnly) { "  --files-only" } elseif ($dirsOnly) { "  --dirs-only" } else { "" }
    $root = Get-Item (Get-Location).Path

    $ignorePatterns = @()
    $ignoreLabel    = ""
    if ($clean) {
        $ignorePatterns = Get-IgnorePatterns
        $gitignorePath  = Join-Path (Get-Location).Path ".gitignore"
        $ignoreLabel    = if (Test-Path $gitignorePath) { "  --clean (.gitignore)" } else { "  --clean (scaffx.ignore)" }
    }

    $count = (Get-ChildItem -LiteralPath $root.FullName -Recurse -ErrorAction SilentlyContinue).Count
    if ($count -gt 200 -and -not (Confirm "el directorio tiene $count elementos!")) { return }

    $rootName = $root.Name
    Write-Header "tree      ->  $rootName$filterLabel$ignoreLabel"

    Get-TreeLines -path $root.FullName -prefix "  " -depth 0 -maxDepth $maxDepth `
                  -onlyFiles $filesOnly -onlyDirs $dirsOnly -ignorePatterns $ignorePatterns

    Write-Host ""
}

function Write-Snapshot {
    $rootItem    = Get-Item (Get-Location).Path

    $ignorePatterns = @()
    $ignoreLabel    = ""
    if ($clean) {
        $ignorePatterns = Get-IgnorePatterns
        $gitignorePath  = Join-Path (Get-Location).Path ".gitignore"
        $ignoreLabel    = if (Test-Path $gitignorePath) { " --clean (.gitignore)" } else { " --clean (scaffx.ignore)" }
    }

    $count = (Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -ErrorAction SilentlyContinue).Count
    if ($count -gt 200 -and -not (Confirm "el directorio tiene $count elementos!")) { return }

    $rootName    = $rootItem.Name
    $outFile     = Join-Path $rootItem.FullName "$rootName.yaml"
    $filterLabel = if ($filesOnly) { " --files-only" } elseif ($dirsOnly) { " --dirs-only" } else { "" }

    Write-Header "snapshot  ->  $rootName.yaml$filterLabel$ignoreLabel"

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("root:")

    $children = Build-YamlLines -path $rootItem.FullName -depth 1 -indentSize 2 `
                                -onlyFiles $filesOnly -onlyDirs $dirsOnly `
                                -ignorePatterns $ignorePatterns

    $outFileName = "$rootName.yaml"
    foreach ($line in $children) {
        if ($line.Trim() -ne "- $outFileName") {
            $lines.Add($line)
        }
    }

    Set-Content $outFile ($lines -join "`n") -Encoding UTF8

    Write-Row "file" "$rootName.yaml" "ok"
    Write-Row "path" $outFile "skip"
    Write-Host ""
}

# -- Router -------------------------------------------------------------------

switch ($cmd1) {
    "tree" {
        if ($cmd2 -match '^\d+$') {
            Show-Tree -maxDepth ([int]$cmd2)
        } else {
            Show-Tree
        }
    }
    "snapshot" { Write-Snapshot }
    default    { Show-Help }
}