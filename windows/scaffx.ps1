param(
    [string]$cmd1,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$rest
)

$DIRSIZELIMIT = 200

$FILETEMPLATES = Join-Path $PSScriptRoot "templates/files"
# $ARCHTEMPLATES = Join-Path $PSScriptRoot "templates/architectures"

# -- Parse flags and positional args from $rest -------------------------------

$flags = $rest | Where-Object { $_ -like "--*" }
$positional = $rest | Where-Object { $_ -notlike "--*" }
$cmd2 = if ($positional.Count -gt 0) { $positional[0] } else { "" }

$filesOnly = $flags -contains "--files-only"
$dirsOnly = $flags -contains "--dirs-only"
$clean = $flags -contains "--clean"
$pathMode = $flags -contains "--path"

if ($filesOnly -and $dirsOnly) {
    Write-Host ""
    Write-Host "  error  --files-only y --dirs-only no pueden usarse juntos" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# Flags incompatibles por comando
$fileOnlyCommands = @("count", "size")         # --dirs-only no aplica
$cleanOnlyCommands = @("ignore", "watch", "find", "count", "size", "diff") # --clean no aplica
$pathOnlyCommands = @("watch", "diff", "snapshot", "count", "size")

if (($filesOnly -or $dirsOnly) -and $cmd1 -in @("watch", "diff", "ignore")) {
    Write-Host ""
    Write-Host "  error  --files-only / --dirs-only no son compatibles con '$cmd1'" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($dirsOnly -and $cmd1 -in $fileOnlyCommands) {
    Write-Host ""
    Write-Host "  error  --dirs-only no es compatible con '$cmd1'" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($clean -and $cmd1 -in $cleanOnlyCommands) {
    Write-Host ""
    Write-Host "  error  --clean no es compatible con '$cmd1'" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if ($pathMode -and $cmd1 -in $pathOnlyCommands) {
    Write-Host ""
    Write-Host "  error  --path no es compatible con '$cmd1'" -ForegroundColor Red
    Write-Host ""
    exit 1
}

# -- Command table ------------------------------------------------------------

$COMMANDS = @(
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx tree"; Desc = "muestra representacion visual de la arquitectura de archivos" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx tree <depth>"; Desc = "limita la profundidad del arbol (ej: scaffx tree 2)" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx snapshot"; Desc = "genera <raiz>.yaml con la estructura actual del folder" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx count"; Desc = "muestra la cantidad de archivos en el directorio actual" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx size"; Desc = "muestra el peso total del directorio actual" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx find <patron>"; Desc = "busca en el arbol por nombre — usa comillas para wildcards (ej: '*.json')" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx diff"; Desc = "compara la estructura actual contra el snapshot .yaml existente" },
    [PSCustomObject]@{ Group = "inspect"; Cmd = "scaffx watch"; Desc = "monitorea cambios en el directorio en tiempo real (Ctrl+C para salir)" },
    [PSCustomObject]@{ Group = "ignore"; Cmd = "scaffx ignore"; Desc = "muestra que archivos/carpetas estan siendo ignorados actualmente" },
    [PSCustomObject]@{ Group = "flags"; Cmd = "  --files-only"; Desc = "incluye solo archivos (tree / snapshot / count / find)" },
    [PSCustomObject]@{ Group = "flags"; Cmd = "  --dirs-only"; Desc = "incluye solo directorios (tree / snapshot / find)" },
    [PSCustomObject]@{ Group = "flags"; Cmd = "  --clean"; Desc = "omite entradas segun .gitignore o scaffx.ignore (tree / snapshot)" },
    [PSCustomObject]@{ Group = "flags"; Cmd = "  --path"; Desc = "muestra paths en lugar de arbol visual (tree / find / ignore)" }
)

# -- UI helpers ---------------------------------------------------------------

function Write-Header([string]$rootName, [string]$command, [string]$flags = "", [string]$extra = "") {
    $indent = "  "
    $arrow = " ->"
    $minArrowCol = 30
    $prefix = "$indent$rootName"
    $padding = [Math]::Max($minArrowCol - $prefix.Length, 1)
    $right = ($(@($command, $flags, $extra) | Where-Object { $_ }) -join "  ")
    $line = "$prefix$(' ' * $padding)$arrow  $right"
    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host "  $('-' * ($line.Length - $indent.Length))" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Row([string]$label, [string]$msg, [string]$status = "ok") {
    $icon = switch ($status) { "ok" { "+" } "warn" { "warn" } "skip" { "-" } "none" { " " } default { " " } }
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
    Write-Header "scaffx" "help"
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

function Get-Root { return Get-Item (Get-Location).Path }

function Confirm([string]$msg, [string]$qst) {
    Write-Host ""
    Write-Row "" $msg "warn"
    $reply = Read-Host "  " $qst " [Y/n]"
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

function Get-FilterLabel {
    if ($filesOnly) { return "  --files-only" }
    if ($dirsOnly)  { return "  --dirs-only" }
    return ""
}

function Get-IgnoreContext {
    if (-not $clean) { return @{ patterns = @(); label = "" } }
    $patterns = Get-IgnorePatterns
    $gitignorePath = Join-Path (Get-Location).Path ".gitignore"
    $label = if (Test-Path $gitignorePath) { "  --clean (.gitignore)" } else { "  --clean (scaffx.ignore)" }
    return @{ patterns = $patterns; label = $label }
}

function Get-VisibleItems([string]$path, [bool]$onlyFiles, [bool]$onlyDirs) {
    $all = Get-ChildItem -LiteralPath $path | Sort-Object { $_.PSIsContainer -eq $false }, Name
    if ($onlyFiles) { return $all | Where-Object { -not $_.PSIsContainer } }
    if ($onlyDirs)  { return $all | Where-Object { $_.PSIsContainer } }
    return $all
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
        $_ -and $_ -notmatch '^\s*#'
    } | ForEach-Object { $_.Trim() }

    return $patterns
}

function Test-Ignored {
    param(
        [System.IO.FileSystemInfo]$item,
        [string[]]$patterns
    )

    if (-not $patterns -or $patterns.Count -eq 0) { return $false }

    $name = $item.Name
    $fullPath = $item.FullName -replace '\\', '/'

    foreach ($pattern in $patterns) {
        $p = $pattern -replace '\\', '/'

        if ($p.EndsWith('/')) {
            if ($item.PSIsContainer) {
                $dirPattern = $p.TrimEnd('/')
                if ($name -like $dirPattern) { return $true }
            }
            continue
        }

        if ($p -match '/') {
            if ($fullPath -like "*/$p") { return $true }
            if ($fullPath -like "*/$p/*") { return $true }
        } else {
            if ($name -like $p) { return $true }
        }
    }

    return $false
}

function Get-DirItemCount([string]$path, [bool]$filesOnly = $false) {
    $params = @{ LiteralPath = $path; Recurse = $true; ErrorAction = "SilentlyContinue" }
    if ($filesOnly) { $params["File"] = $true }
    return (Get-ChildItem @params).Count
}

function Get-TreeLines {
    param(
        [string]$path,
        [string]$prefix = "",
        [int]$depth = 0,
        [int]$maxDepth = -1,
        [bool]$onlyFiles = $false,
        [bool]$onlyDirs = $false,
        [bool]$pathMode = $false,
        [string[]]$ignorePatterns = @(),
        [string[]]$filterPatterns = @(),
        [string[]]$ignoreHighlight = @()
    )

    if ($maxDepth -ge 0 -and $depth -ge $maxDepth) { return }

    $visible = Get-VisibleItems -path $path -onlyFiles $onlyFiles -onlyDirs $onlyDirs
    if ($ignorePatterns.Count -gt 0) {
        $visible = $visible | Where-Object { -not (Test-Ignored -item $_ -patterns $ignorePatterns) }
    }
    
    if ($filterPatterns.Count -gt 0) {
        $visible = $visible | Where-Object {
            $item = $_
            if ($item.PSIsContainer) {
                (Get-ChildItem -LiteralPath $item.FullName -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $n = $_.Name; $filterPatterns | Where-Object { $n -like $_ } }).Count -gt 0
            } else {
                $filterPatterns | Where-Object { $item.Name -like $_ }
            }
        }
    }

    if ($ignoreHighlight.Count -gt 0) {
        $visible = $visible | Where-Object {
            $item = $_
            $isIgnored = Test-Ignored -item $item -patterns $ignoreHighlight
            if ($isIgnored) { return $true }
            if ($item.PSIsContainer) {
                (Get-ChildItem -LiteralPath $item.FullName -Recurse -ErrorAction SilentlyContinue |
                Where-Object { Test-Ignored -item $_ -patterns $ignoreHighlight }).Count -gt 0
            } else { $false }
        }
    }

    for ($i = 0; $i -lt $visible.Count; $i++) {
        $item = $visible[$i]
        $isLast = ($i -eq $visible.Count - 1)
        $branch = if ($isLast) { "└── " } else { "├── " }
        $childPfx = if ($isLast) { "    " } else { "│   " }

        $isIgnoredItem = $ignoreHighlight.Count -gt 0 -and (Test-Ignored -item $item -patterns $ignoreHighlight)

        if ($item.PSIsContainer) {
            $dirColor = if ($isIgnoredItem) { "Yellow" } else { "Cyan" }
            if ($pathMode) {
                Write-Host "  $($item.FullName)\" -ForegroundColor $dirColor
                if (-not $isIgnoredItem) {
                    Get-TreeLines -path $item.FullName -prefix "$prefix$childPfx" -depth ($depth + 1) `
                        -maxDepth $maxDepth -onlyFiles $onlyFiles -onlyDirs $onlyDirs `
                        -ignorePatterns $ignorePatterns -filterPatterns $filterPatterns `
                        -ignoreHighlight $ignoreHighlight -pathMode $pathMode
                }
            } else {
                Write-Host "$prefix$branch" -ForegroundColor DarkGray -NoNewline
                $itemName = $item.Name
                Write-Host "$itemName/" -ForegroundColor $dirColor
                if (-not $isIgnoredItem) {
                    Get-TreeLines -path $item.FullName -prefix "$prefix$childPfx" -depth ($depth + 1) `
                        -maxDepth $maxDepth -onlyFiles $onlyFiles -onlyDirs $onlyDirs `
                        -ignorePatterns $ignorePatterns -filterPatterns $filterPatterns `
                        -ignoreHighlight $ignoreHighlight -pathMode $pathMode
                }
            }
        } else {
            $matchParam = $filterPatterns.Count -eq 0 -or ($filterPatterns | Where-Object { $item.Name -like $_ })
            if (-not $matchParam) { continue }
            $nameColor = if ($isIgnoredItem) { "Yellow" } elseif ($filterPatterns.Count -gt 0) { "Green" } else { "Gray" }
            if ($pathMode) {
                Write-Host "  $($item.FullName)" -ForegroundColor $nameColor
            } else {
                Write-Host "$prefix$branch" -ForegroundColor DarkGray -NoNewline
                Write-Host $item.Name -ForegroundColor $nameColor
            }
        }
    }
}

function Build-YamlLines {
    param(
        [string]$path,
        [int]$depth = 0,
        [int]$indentSize = 2,
        [bool]$onlyFiles = $false,
        [bool]$onlyDirs = $false,
        [string[]]$ignorePatterns = @()
    )

    $lines = [System.Collections.Generic.List[string]]::new()
    $indent = " " * ($depth * $indentSize)

    $visible = Get-VisibleItems -path $path -onlyFiles $onlyFiles -onlyDirs $onlyDirs
    if ($ignorePatterns.Count -gt 0) {
        $visible = $visible | Where-Object { -not (Test-Ignored -item $_ -patterns $ignorePatterns) }
    }

    foreach ($item in $visible) {
        if ($item.PSIsContainer) {
            $lines.Add("${indent}- $($item.Name):")
            $children = Build-YamlLines -path $item.FullName -depth ($depth + 1) `
                -indentSize $indentSize -onlyFiles $onlyFiles -onlyDirs $onlyDirs `
                -ignorePatterns $ignorePatterns
            foreach ($child in $children) { $lines.Add($child) }
        } else {
            $lines.Add("${indent}- $($item.Name)")
        }
    }

    return $lines
}

# Recorre el YAML y devuelve un set plano de rutas relativas
function Get-YamlPaths([string]$yamlFile) {
    $paths = [System.Collections.Generic.HashSet[string]]::new()
    $stack = [System.Collections.Generic.List[string]]::new()
    $content = Get-Content $yamlFile

    $rootName = ($content | Select-Object -First 1) -replace ':\s*$', ''

    foreach ($rawLine in $content) {
        $trimmed = $rawLine.Trim()
        if (-not $trimmed -or $trimmed -eq "${rootName}:") { continue }
        if ($trimmed -notmatch '^-\s+') { continue }

        $isDir = $trimmed -match ':\s*$'
        $entry = $trimmed -replace '^-\s+', '' -replace ':\s*$', ''

        $indentLen = $rawLine.Length - ($rawLine -replace '^\ +', '').Length
        $level = [math]::Floor($indentLen / 2)

        while ($stack.Count -ge $level) { $stack.RemoveAt($stack.Count - 1) }

        $relPath = if ($stack.Count -gt 0) { ($stack -join '/') + '/' + $entry } else { $entry }

        $paths.Add($relPath) | Out-Null
        if ($isDir) { $stack.Add($entry) } 
    }

    return $paths
}

# -- Commands -----------------------------------------------------------------

function Show-Tree {
    param([int]$maxDepth = -1)

    $root = Get-Root
    $filterLabel = Get-FilterLabel
    $ignoreCtx = Get-IgnoreContext
    $count = Get-DirItemCount -path $root.FullName -filesOnly $filesOnly
    
    if ($count -gt $DIRSIZELIMIT -and -not (Confirm "el directorio tiene $count elementos!" "Desea continuar?")) { return }

    Write-Header $root.Name "tree" "$filterLabel$($ignoreCtx.label)".Trim()
    Get-TreeLines -path $root.FullName -prefix "  " -depth 0 -maxDepth $maxDepth `
        -onlyFiles $filesOnly -onlyDirs $dirsOnly -ignorePatterns $ignoreCtx.patterns -pathMode $pathMode
}

function Write-Snapshot { 
    $rootItem = Get-Root
    
    $ignoreCtx = Get-IgnoreContext
    $count = Get-DirItemCount -path $rootItem.FullName -filesOnly $filesOnly
    $rootName = $rootItem.Name
    $outFile = Join-Path $rootItem.FullName "$rootName.yaml"
    $filterLabel = Get-FilterLabel

    if ($count -gt $DIRSIZELIMIT -and -not (Confirm "el directorio tiene $count elementos!" "Desea continuar?")) { return }

    Write-Header $rootItem.Name "snapshot" "$filterLabel$($ignoreCtx.label)".Trim()
    
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("${rootName}:")

    $children = Build-YamlLines -path $rootItem.FullName -depth 1 -indentSize 2 `
        -onlyFiles $filesOnly -onlyDirs $dirsOnly `
        -ignorePatterns $ignoreCtx.patterns

    $outFileName = "$rootName.yaml"
    foreach ($line in $children) {
        if ($line.Trim() -ne "- $outFileName") { $lines.Add($line) }
    }

    Set-Content $outFile ($lines -join "`n") -Encoding UTF8

    Write-Row "file" "$rootName.yaml" "ok"
    Write-Row "path" $outFile "skip"
    Write-Host ""
}

function Show-Count {
    $root = Get-Root
    $filterLabel = Get-FilterLabel
    $count = Get-DirItemCount -path $root.FullName -filesOnly $filesOnly

    Write-Header $root.Name "count" $filterLabel.Trim()
    Write-Row "archivos" "$count elementos" "ok"
    Write-Host ""
}

function Show-Size {
    $root = Get-Root
    $count = Get-DirItemCount -path $root.FullName -filesOnly $true

    if ($count -gt $DIRSIZELIMIT -and -not (Confirm "el directorio tiene $count archivos, puede tardar" "Desea continuar?")) { return }

    $bytes = (Get-ChildItem -LiteralPath $root.FullName -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum

    $sizeStr = if ($bytes -ge 1GB) { "{0:N2} GB" -f ($bytes / 1GB) }
    elseif ($bytes -ge 1MB) { "{0:N2} MB" -f ($bytes / 1MB) }
    elseif ($bytes -ge 1KB) { "{0:N2} KB" -f ($bytes / 1KB) }
    else { "$bytes B" }

    Write-Header $root.Name "size"
    Write-Row "peso" $sizeStr "ok"
    Write-Host ""
}


function Show-Find {
    $patterns = $positional

    if (-not $patterns -or $patterns.Count -eq 0) {
        Write-Fail "uso: scaffx find <patron...>  (ej: scaffx find '*.json' '*.exe')"
        return
    }

    $root = Get-Root
    $filterLabel = Get-FilterLabel
    $patternLabel = ($patterns | ForEach-Object { "'$_'" }) -join "  "

    $pairs = Get-ChildItem -LiteralPath $root.FullName -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $n = $_.Name; $patterns | Where-Object { $n -like $_ } }
    $pairs = if ($filesOnly) { $pairs | Where-Object { -not $_.PSIsContainer } }
    elseif ($dirsOnly) { $pairs | Where-Object { $_.PSIsContainer } }
    else { $pairs }

    Write-Header $root.Name "find" $filterLabel.Trim() $patternLabel

    if (@($pairs).Count -eq 0) {
        Write-Row "result" "sin coincidencias" "none"
        Write-Host ""
        return
    }

    Get-TreeLines -path $root.FullName -prefix "  " -depth 0 `
        -onlyFiles $filesOnly -onlyDirs $dirsOnly -filterPatterns $patterns -pathMode $pathMode

    Write-Host ""
    Write-Row "total" "$(@($pairs).Count) coincidencias" "ok"
    Write-Host ""
}


function Show-Diff {
    $rootItem = Get-Root
    $rootName = $rootItem.Name
    $yamlFile = Join-Path $rootItem.FullName "$rootName.yaml"

    if (-not (Test-Path $yamlFile)) {
        Write-Fail "no se encontro snapshot '$rootName.yaml' — ejecuta 'scaffx snapshot' primero"
        return
    }

    $count = Get-DirItemCount -path $rootItem.FullName -filesOnly $false
    if ($count -gt $DIRSIZELIMIT -and -not (Confirm "el directorio tiene $count elementos!" "Desea continuar?")) { return }

    Write-Header $rootItem.Name "diff" "" "$rootName.yaml"

    $current = [System.Collections.Generic.HashSet[string]]::new()
    Get-ChildItem -LiteralPath $rootItem.FullName -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "$rootName.yaml" } |
    ForEach-Object {
        $rel = $_.FullName.Substring($rootItem.FullName.Length).TrimStart('\', '/') -replace '\\', '/'
        $current.Add($rel) | Out-Null
    }

    $snapshot = Get-YamlPaths -yamlFile $yamlFile

    $added = $current | Where-Object { -not $snapshot.Contains($_) } | Sort-Object
    $removed = $snapshot | Where-Object { -not $current.Contains($_) } | Sort-Object

    if ((-not $added -or @($added).Count -eq 0) -and (-not $removed -or @($removed).Count -eq 0)) {
        Write-Row "status" "sin diferencias" "ok"
        Write-Host ""
        return
    }

    foreach ($a in $added) { Write-Row "" $a "ok" }
    foreach ($r in $removed) { Write-Row "" $r "skip" }

    Write-Host ""
    $addedCount = if ($added) { @($added).Count }   else { 0 }
    $removedCount = if ($removed) { @($removed).Count } else { 0 }
    Write-Row "resumen" "+$addedCount añadidos   -$removedCount eliminados" "none"
    Write-Host ""
}

function Start-Watch {
    $root = Get-Item (Get-Location).Path

    Write-Header $root.Name "watch"
    Write-Row "estado" "monitoreando... (Ctrl+C para salir)" "warn"
    Write-Host ""

    $watcher = [System.IO.FileSystemWatcher]::new($root.FullName)
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true

    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        $time = Get-Date -Format "HH:mm:ss"

        $icon = switch ($changeType) {
            "Created" { "+" }
            "Deleted" { "-" }
            "Renamed" { "~" }
            default { "." }
        }
        $color = switch ($changeType) {
            "Created" { "Green" }
            "Deleted" { "Red" }
            "Renamed" { "Yellow" }
            default { "DarkGray" }
        }

        Write-Host "  " -NoNewline
        Write-Host "$time  " -ForegroundColor DarkGray -NoNewline
        Write-Host "$icon  " -ForegroundColor $color -NoNewline
        Write-Host $path -ForegroundColor Gray
    }

    $jobs = @(
        Register-ObjectEvent $watcher Created -Action $action
        Register-ObjectEvent $watcher Deleted -Action $action
        Register-ObjectEvent $watcher Renamed -Action $action
    )

    try {
        while ($true) { Start-Sleep -Milliseconds 200 }
    } finally {
        $jobs | ForEach-Object { Unregister-Event -SubscriptionId $_.Id }
        $watcher.Dispose()
        Write-Host ""
        Write-Row "estado" "watch detenido" "skip"
        Write-Host ""
    }
}

function Show-Ignored {
    $root = Get-Root
    $patterns = Get-IgnorePatterns

    $gitignorePath = Join-Path $root.FullName ".gitignore"
    $source = if (Test-Path $gitignorePath) { ".gitignore" } else { "scaffx.ignore" }

    Write-Header $root.Name "ignore" "" $source

    if (-not $patterns -or $patterns.Count -eq 0) {
        Write-Row "info" "no se encontro archivo de ignore" "none"
        Write-Host ""
        return
    }

    $ignored = [System.Collections.Generic.List[object]]::new()
    $queue   = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($root.FullName)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        foreach ($item in (Get-ChildItem -LiteralPath $current -ErrorAction SilentlyContinue)) {
            if (Test-Ignored -item $item -patterns $patterns) {
                $ignored.Add($item)
            } elseif ($item.PSIsContainer) {
                $queue.Enqueue($item.FullName)
            }
        }
    }


    if (-not $ignored -or @($ignored).Count -eq 0) {
        Write-Row "info" "patrones definidos pero ninguna entrada coincide" "none"
        Write-Host ""

        Write-Host "  patrones activos:" -ForegroundColor DarkGray
        foreach ($p in $patterns) {
            Write-Host "    $p" -ForegroundColor DarkGray
        }
        Write-Host ""
        return
    }

    Get-TreeLines -path $root.FullName -prefix "  " -depth 0 `
    -onlyFiles $false -onlyDirs $false -ignoreHighlight $patterns -pathMode $pathMode

    Write-Host ""
    Write-Row "total" "$(@($ignored).Count) entradas ignoradas" "skip"
    Write-Host ""
}

# -- Router -------------------------------------------------------------------

switch ($cmd1) {
    "tree" {
        if ($cmd2 -match '^\d+$') { Show-Tree -maxDepth ([int]$cmd2) }
        else { Show-Tree }
    }
    "snapshot" { Write-Snapshot }
    "count" { Show-Count }
    "size" { Show-Size }
    "find" { Show-Find }
    "diff" { Show-Diff }
    "watch" { Start-Watch }
    "ignore" { Show-Ignored }
    default { Show-Help }
}