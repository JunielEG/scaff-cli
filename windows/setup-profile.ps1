param($InstallDir)

$profileFile = $PROFILE
$profileDir  = Split-Path $profileFile
$toolCmd = "scaffx"

if (-not (Test-Path $profileDir)) { New-Item -ItemType Directory -Path $profileDir | Out-Null }

$block = @'

# $toolCmd [start]
function cppx { & "$InstallDir\cppx.ps1" @args }
Register-ArgumentCompleter -CommandName cppx -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $tokens = $commandAst.CommandElements
    $cmd1   = if ($tokens.Count -gt 1) { $tokens[1].Value } else { "" }

    $commands = @{
        ""    = @("tree", "snapshot")
    }

    $completing = if ($tokens.Count -eq 1) { "" }
                  elseif ($tokens.Count -eq 2 -and $wordToComplete -ne "") { "" }
                  elseif ($commands.ContainsKey($cmd1)) { $cmd1 }
                  else { $null }

    if ($null -ne $completing) {
        $commands[$completing] | Where-Object { $_ -like "$wordToComplete*" } | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
# $toolCmd [end]
'@

$block = $block.Replace('$InstallDir', $InstallDir)
$block = $block.Replace('$toolCmd',    $toolCmd)

if (Test-Path $profileFile) {
    $content = Get-Content $profileFile -Raw

if ($content -match "(?s)# $toolCmd \[start\].*?# $toolCmd \[end\]") {
    $pattern = "(?s)# $toolCmd \[start\].*?# $toolCmd \[end\]"
    $replacement = $block.Trim()
    $content = [regex]::Replace($content, $pattern, { $replacement })
    Set-Content -Path $profileFile -Value $content
    Write-Host "  profile   ^  autocomplete updated"
    } else {
        # No existe, agregar al final
        Add-Content -Path $profileFile -Value $block
        Write-Host "  profile   ^  autocomplete added"
    }
} else {
    Set-Content -Path $profileFile -Value $block
    Write-Host "  profile   ^  autocomplete added"
}