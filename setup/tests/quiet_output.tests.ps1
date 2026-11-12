<#
.SYNOPSIS
  Tests for Setup's quiet tool output (Invoke-Logged in setup\setup.ps1), plain
  PowerShell 5.1. A fake tool prints thousands of compiler warnings, ninja
  progress and kit "==>" steps; the screen must show only progress, steps and,
  on failure, the real error lines; setup.log must get every line.
  Exit 0 = all pass.
#>
$ErrorActionPreference = "Stop"
$setupDir = Split-Path $PSScriptRoot -Parent
$script:failed = 0
function Assert([bool]$Cond, [string]$Msg) {
    if ($Cond) { Write-Host "PASS $Msg" } else { Write-Host "FAIL $Msg" -ForegroundColor Red; $script:failed++ }
}

$tmp = Join-Path $env:TEMP ("quiet out-" + [guid]::NewGuid().ToString("N").Substring(0, 8))
New-Item -ItemType Directory -Path $tmp | Out-Null

# Fake tool: <warnings> warning lines (3 per "file"), ninja progress, steps, optional error, exit code.
Set-Content -LiteralPath "$tmp\fake tool.ps1" -Value @'
param([int]$Warnings, [int]$Exit, [switch]$Ninja, [switch]$Fail)
Write-Host "==> 1/2 first step"
for ($i = 1; $i -le $Warnings; $i++) {
    Write-Host "C:\x\ppu_memory.h($i,38): warning: implicit conversion loses integer precision [-Wimplicit-int-conversion]"
    Write-Host "C:\x\include\psemu/error_codes.h(12,9): note: expanded from macro 'CELL_EFAULT'"
    if ($Ninja -and $i % 1000 -eq 0) { Write-Host ("[{0}/3] Building C object file{0}.obj" -f ($i / 1000)) }
}
Write-Host "==> 2/2 second step"
if ($Fail) {
    Write-Host "C:\x\a.c(3,1): error: use of undeclared identifier 'foo'"
    Write-Host "FAILED: CMakeFiles/x.dir/a.c.obj"
    Write-Host "ninja: build stopped: subcommand failed."
}
exit $Exit
'@

# Driver: real kitlib + the real Invoke-Logged taken from setup.ps1's syntax tree.
Set-Content -LiteralPath "$tmp\driver.ps1" -Value @'
param([string]$SetupDir, [string]$Log, [string]$Tool, [switch]$ShowAll, [string]$ToolArgs)
$ErrorActionPreference = "Stop"
. (Join-Path $SetupDir "kitlib.ps1")
$ast = [Management.Automation.Language.Parser]::ParseFile((Join-Path $SetupDir "setup.ps1"), [ref]$null, [ref]$null)
$fn = $ast.Find({ param($n) $n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq "Invoke-Logged" }, $true)
. ([scriptblock]::Create($fn.Extent.Text))
try {
    Invoke-Logged "Building" "powershell.exe" (@("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $Tool) + ($ToolArgs -split ","))
    Write-Host "RETURNED"
} catch { Write-Host "THREW: $($_.Exception.Message)" }
'@

function Run-Case([string]$Name, [string[]]$ToolArgs, [switch]$ShowAll) {
    $log = "$tmp\$Name.log"
    $a = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "$tmp\driver.ps1", "-SetupDir", $setupDir,
           "-Log", $log, "-Tool", "$tmp\fake tool.ps1")
    if ($ShowAll) { $a += "-ShowAll" }
    $a += "-ToolArgs"; $a += ($ToolArgs -join ",")
    $ErrorActionPreference = "Continue"
    $out = & powershell.exe @a 2>&1 | Out-String
    $ErrorActionPreference = "Stop"
    return @{ Out = $out; Log = (Get-Content -LiteralPath $log -Raw) }
}

try {
    # ---- success, compiling (ninja progress) ----
    $r = Run-Case "ok" @("-Warnings", "3000", "-Exit", "0", "-Ninja")
    Assert ($r.Out -match "RETURNED") "success -> returns"
    Assert ($r.Out -notmatch "warning:" -and $r.Out -notmatch "error_codes") "success -> no warning/note lines on screen"
    Assert ($r.Out -match "Building: 3 of 3 files \(100%\)") "success -> progress line 'Building: 3 of 3 files (100%)'"
    Assert ($r.Out -match "1/2 first step" -and $r.Out -match "2/2 second step") "success -> kit '==>' steps shown"
    Assert (([regex]::Matches($r.Log, "warning:")).Count -eq 3000) "success -> all 3000 warnings in setup.log"
    $lines = @($r.Out -split "`n" | Where-Object { $_.Trim() }).Count
    Assert ($lines -le 10) "success -> screen stays short ($lines non-empty lines for 6000+ tool lines)"

    # ---- failure: only the real error lines are shown ----
    $r = Run-Case "fail" @("-Warnings", "500", "-Exit", "1", "-Fail")
    Assert ($r.Out -match "THREW: Building failed \(exit code 1\)") "failure -> throws with exit code"
    Assert ($r.Out -match "error: use of undeclared identifier 'foo'" -and $r.Out -match "FAILED: CMakeFiles") "failure -> real error lines in the message"
    Assert ($r.Out -notmatch "warning:") "failure -> warnings not in the message"
    Assert ($r.Log -match "error: use of undeclared") "failure -> error also in setup.log"

    # ---- failure without recognisable error lines: last lines instead ----
    $r = Run-Case "fail-plain" @("-Warnings", "0", "-Exit", "3")
    Assert ($r.Out -match "THREW: Building failed \(exit code 3\)" -and $r.Out -match "2/2 second step") "failure, no error lines -> last tool lines in the message"

    # ---- no ninja: elapsed-seconds line instead of a file count ----
    $r = Run-Case "plain" @("-Warnings", "100", "-Exit", "0")
    Assert ($r.Out -match "Building\.\.\. \d+ s" -and $r.Out -notmatch "warning:") "no ninja -> 'Building... N s', no warnings"

    # ---- -ShowAll: everything, as before ----
    $r = Run-Case "all" @("-Warnings", "10", "-Exit", "0") -ShowAll
    Assert (([regex]::Matches($r.Out, "warning:")).Count -eq 10) "-ShowAll -> warnings on screen"
}
finally {
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
}
if ($script:failed) { Write-Host "$script:failed FAILED" -ForegroundColor Red; exit 1 }
Write-Host "ALL PASS"
exit 0
