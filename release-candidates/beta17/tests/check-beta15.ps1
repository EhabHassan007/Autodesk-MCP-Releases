$ErrorActionPreference='Stop'
$root=(Join-Path $PSScriptRoot '../source/runtime')
$failures=@()
Get-ChildItem $root -Filter *.ps1 -Recurse | ForEach-Object {
 $tokens=$null; $errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors)
 if($errors){$failures+= $errors}
}
if($failures.Count){throw ($failures | Out-String)}
'PASS: all PowerShell files parse'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('beta15-check-'+[guid]::NewGuid())
$env:LOCALAPPDATA=Join-Path $testRoot 'local';$env:APPDATA=Join-Path $testRoot 'roaming';$env:ProgramFiles=Join-Path $testRoot 'programs'
New-Item -ItemType Directory -Force $env:LOCALAPPDATA,$env:APPDATA,$env:ProgramFiles | Out-Null
. "$root/installer/Setup-BimCad.ps1" -LibraryOnly
$pkg=Join-Path $env:LOCALAPPDATA 'Packages/Claude_Test/LocalCache/Roaming/Claude'
New-Item -ItemType Directory -Force $pkg | Out-Null
$paths=@(Get-ClaudeDesktopConfigPaths)
if($paths.Count -ne 2){throw 'Expected roaming and MSIX paths'}
foreach($path in $paths){
 New-Item -ItemType Directory -Force (Split-Path $path) | Out-Null
 [IO.File]::WriteAllText($path,'{"mcpServers":{"keep":{"command":"keep.exe"},"autodesk":{"command":"old.exe"}}}')
 Register-ClaudeDesktopMcpServer -Name 'Autodesk MCP Connector' -Bridge "$root/src/autodesk/autodesk-bridge.ps1" -LegacyNames @('autodesk') -ConfigPath $path
 $bytes=[IO.File]::ReadAllBytes($path)
 if($bytes.Length -ge 3 -and $bytes[0]-eq 239 -and $bytes[1]-eq 187 -and $bytes[2]-eq 191){throw 'Unexpected BOM'}
 $cfg=Get-Content $path -Raw | ConvertFrom-Json
 if(-not $cfg.mcpServers.keep -or -not $cfg.mcpServers.'Autodesk MCP Connector' -or $cfg.mcpServers.autodesk){throw 'Preservation/registration failed'}
}
'PASS: roaming/MSIX config, no BOM, preserved unrelated entry, removed legacy entry'
function Get-ClaudeDesktopProcesses { @() }
function Get-ClaudeDesktopInstallation { [pscustomobject]@{Installed=$true} }
function Get-OptionalCommand { param($Name) if($Name -eq 'codex'){'mock-codex'} }
function Register-McpServer { throw 'simulated Codex failure' }
function Restart-ClaudeDesktopIfRunning { }
$reported=$false
try { Register-DetectedAiClients $root }
catch { if($_.Exception.Message -notmatch 'Codex: simulated Codex failure'){throw}; $reported=$true }
if(-not $reported){throw 'Partial registration failure was hidden'}
'PASS: Codex failure does not block Claude registration and is reported'
# A broken config must survive unchanged, without blocking the other config path.
function Get-OptionalCommand { param($Name) if($Name -eq 'claude'){'mock-claude'} }
function Register-ClaudeCodeMcpServer { throw 'simulated Claude Code failure' }
[IO.File]::WriteAllText($paths[0],'{invalid json')
[IO.File]::WriteAllText($paths[1],'{"mcpServers":{"keep":{"command":"keep.exe"}}}')
$reported=$false
try { Register-DetectedAiClients $root }
catch {
 if($_.Exception.Message -notmatch 'Claude Code: simulated Claude Code failure' -or $_.Exception.Message -notmatch 'Claude Desktop at'){throw}
 $reported=$true
}
if(-not $reported){throw 'Expected config failure report'}
if([IO.File]::ReadAllText($paths[0]) -ne '{invalid json'){throw 'Malformed original config was changed'}
$cfg=Get-Content $paths[1] -Raw | ConvertFrom-Json
if(-not $cfg.mcpServers.'Autodesk MCP Connector' -or -not $cfg.mcpServers.keep){throw 'Second config path was not updated'}
'PASS: Claude Code and one malformed config do not block the other path; original malformed file preserved'
Remove-Item $testRoot -Recurse -Force
