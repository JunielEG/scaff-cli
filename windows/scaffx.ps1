param(
    [string]$cmd1,
    [Parameter(ValueFromRemainingArguments=$true)]
    [string[]]$rest
)

# -- Parse flags and positional args from $rest -------------------------------

$flags      = $rest | Where-Object { $_ -like "--*" }
$positional = $rest | Where-Object { $_ -notlike "--*" }
$cmd2       = if ($positional.Count -gt 0) { $positional[0] } else { "" }

$filesOnly = $flags -contains "--files-only"
$dirsOnly  = $flags -contains "--dirs-only"

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
    [PSCustomObject]@{ Group = "flags";   Cmd = "  --dirs-only";        Desc = "incluye solo directorios (tree / snapshot)" }
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

function Get-TreeLines {
    param(
        [string]$path,
        [string]$prefix = "",
        [int]$depth = 0,
        [int]$maxDepth = -1,
        [bool]$onlyFiles = $false,
        [bool]$onlyDirs  = $false
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

    for ($i = 0; $i -lt $visible.Count; $i++) {
        $item     = $visible[$i]
        $isLast   = ($i -eq $visible.Count - 1)
        $branch   = if ($isLast) { "└── " } else { "├── " }
        $childPfx = if ($isLast) { "    " } else { "│   " }

        if ($item.PSIsContainer) {
            Write-Host "$prefix$branch" -ForegroundColor DarkGray -NoNewline
            Write-Host $item.Name -ForegroundColor Cyan
            Get-TreeLines -path $item.FullName -prefix "$prefix$childPfx" -depth ($depth + 1) `
                          -maxDepth $maxDepth -onlyFiles $onlyFiles -onlyDirs $onlyDirs
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
        [bool]$onlyDirs  = $false
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

    foreach ($item in $visible) {
        if ($item.PSIsContainer) {
            $lines.Add("${indent}- $($item.Name):")
            $children = Build-YamlLines -path $item.FullName -depth ($depth + 1) `
                                        -indentSize $indentSize -onlyFiles $onlyFiles -onlyDirs $onlyDirs
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

    $count = (Get-ChildItem -LiteralPath $root.FullName -Recurse -ErrorAction SilentlyContinue).Count
    if ($count -gt 200 -and -not (Confirm "el directorio tiene $count elementos!")) { return }

    $rootName = $root.Name
    Write-Header "tree      ->  $rootName$filterLabel"

    Get-TreeLines -path $root.FullName -prefix "  " -depth 0 -maxDepth $maxDepth `
                  -onlyFiles $filesOnly -onlyDirs $dirsOnly

    Write-Host ""
}

function Write-Snapshot {
    $rootItem    = Get-Item (Get-Location).Path

    $count = (Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -ErrorAction SilentlyContinue).Count
    if ($count -gt 200 -and -not (Confirm "el directorio tiene $count elementos!")) { return }

    $rootName    = $rootItem.Name
    $outFile     = Join-Path $rootItem.FullName "$rootName.yaml"
    $filterLabel = if ($filesOnly) { " --files-only" } elseif ($dirsOnly) { " --dirs-only" } else { "" }

    Write-Header "snapshot  ->  $rootName.yaml$filterLabel"

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("root:")

    $children = Build-YamlLines -path $rootItem.FullName -depth 1 -indentSize 2 `
                                -onlyFiles $filesOnly -onlyDirs $dirsOnly

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