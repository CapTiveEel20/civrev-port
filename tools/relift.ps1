<#
.SYNOPSIS
  Regenerate everything git-ignored: analysis\, the lifted PPU code (src\recomp),
  the HLE NID table (src\gen) and the lifted SPU programs (src\spu_gen).
  Run from anywhere; paths are relative to the project root.

  Defaults assume this folder layout (all side by side):
    ps3recomp\          the ps3recomp checkout, with .venv\ set up
    civrev-gamefiles\   your decrypted EBOOT.elf (kept outside every repo)
    civrev-port\        this project

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools\relift.ps1
  powershell -ExecutionPolicy Bypass -File tools\relift.ps1 -PS3Recomp D:\ps3recomp -Elf D:\civrev\EBOOT.elf
#>
param(
    [string]$PS3Recomp = (Join-Path $PSScriptRoot "..\..\ps3recomp"),
    [string]$Elf       = (Join-Path $PSScriptRoot "..\..\civrev-gamefiles\EBOOT.elf"),
    # Chunk count for the lifted PPU source. More chunks = smaller files that
    # compile in parallel and need less RAM each.
    [int]$Chunks       = 64
)
$ErrorActionPreference = "Stop"
$root  = Split-Path -Parent $PSScriptRoot
$py    = Join-Path $PS3Recomp ".venv\Scripts\python.exe"
$tools = Join-Path $PS3Recomp "tools"
Set-Location $root

# Executable sections of BLES00238's EBOOT (from its section headers):
#   0x00010200 .init, 0x00010240-0x014150D8 .text, .fini,
#   0x0141510C-0x01416CEC import stubs (0x1BE0 bytes = 223 stubs x 0x20).
# --code-end sits just past the stubs, so --hle-stubs can rewrite them and
# nothing above (read-only data in the same segment) is mistaken for code.
$CodeEnd = "0x01416CEC"

function Step($name, [scriptblock]$cmd) {
    Write-Host "==> $name" -ForegroundColor Cyan
    $t = [Diagnostics.Stopwatch]::StartNew()
    & $cmd
    if ($LASTEXITCODE -ne 0) { throw "$name failed (exit $LASTEXITCODE)" }
    Write-Host ("    done in {0:N1} s" -f $t.Elapsed.TotalSeconds)
}

if (-not (Test-Path $Elf)) { throw "Decrypted EBOOT not found: $Elf" }
New-Item -ItemType Directory -Force analysis | Out-Null

Step "1/5 load ELF (functions, imports, TOC)" {
    & $py "$tools\ppu_loader.py" $Elf -o analysis
}
Step "2/5 name imports (for reading only)" {
    & $py "$tools\gen_imports.py" $Elf -o analysis\imports_named.json
}
Step "3/5 lift PPU code to C++" {
    Remove-Item -Recurse -Force src\recomp -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force src\recomp | Out-Null
    & $py "$tools\ppu_lifter.py" $Elf `
        --functions analysis\EBOOT.functions.json `
        --hle-stubs analysis\EBOOT.imports.json `
        --code-end $CodeEnd `
        --chunks $Chunks `
        -o src\recomp
    if ($LASTEXITCODE -ne 0) { return }
    # Import stubs must save r2 like the real PS3 stub (see the tool's docstring).
    & $py "$PSScriptRoot\fix_import_stub_toc.py" src\recomp
}
Step "4/5 HLE NID -> handler table" {
    Remove-Item -Recurse -Force src\gen -ErrorAction SilentlyContinue
    New-Item -ItemType Directory -Force src\gen | Out-Null
    & $py "$tools\gen_hle_nids.py" --all --out src\gen\ppu_hle_nids.cpp
}
Step "5/5 extract + lift SPU programs" {
    Remove-Item -Recurse -Force analysis\spu, src\spu_gen -ErrorAction SilentlyContinue
    & $py "$tools\extract_spu_images.py" $Elf --output analysis\spu
    if ($LASTEXITCODE -ne 0) { return }
    New-Item -ItemType Directory -Force src\spu_gen | Out-Null
    & $py "$tools\build_spu_workloads.py" `
        --images analysis\spu --lifted src\spu_gen `
        --out src\spu_gen\spu_workloads.c `
        --register-fn civrev_spu_register_all --constructor --title civrev
}

$files = Get-ChildItem src\recomp -File
Write-Host ("Lifted: {0} files, {1:N0} MB" -f $files.Count, (($files | Measure-Object Length -Sum).Sum / 1MB)) -ForegroundColor Green
