$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('tasks-test-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $testRoot 'local'
$RepositoryRoot=Join-Path $testRoot 'connector'
$fixtureScripts=Join-Path $RepositoryRoot 'scripts'
New-Item -ItemType Directory $fixtureScripts -Force|Out-Null
@'
param($Action,$RepositoryRoot,$StateRoot,$Day='Friday',$Time='16:30',$AdditionalSkillRoots=@())
@{action=$Action;day=$Day;time=$Time;roots=$AdditionalSkillRoots}|ConvertTo-Json|Set-Content (Join-Path $StateRoot 'test-call.json')
$global:LASTEXITCODE=0
'@|Set-Content (Join-Path $fixtureScripts 'weekly-skill-collection.ps1')
foreach($n in @('collect-skills-for-review.ps1','submit-team-knowledge.ps1','central-skill-sync.ps1','Initialize-SkillService.ps1')){'# test placeholder'|Set-Content (Join-Path $fixtureScripts $n)}
$script:updates=0
function Invoke-TaskSetup {param($Script,$ScriptArguments) $script:updates++}
$source=Get-Content (Join-Path $PSScriptRoot '../source/runtime/scripts/configure-connector-tasks.ps1') -Raw
$body=[scriptblock]::Create($source.Substring($source.IndexOf('# Refresh installed')).Replace('$PSScriptRoot','$fixtureScripts'))
try {
 & $body
 $state=Join-Path $env:LOCALAPPDATA 'AutodeskMcpSkillCollection'
 $call=Get-Content (Join-Path $state 'test-call.json') -Raw|ConvertFrom-Json
 if($call.action -ne 'Enable' -or $script:updates -ne 1){throw 'Initial tasks not configured'}
 Remove-Item (Join-Path $state 'test-call.json')
 @{enabled=$false;day='Monday';time='10:00';additional_skill_roots=@('custom')}|ConvertTo-Json|Set-Content (Join-Path $state 'settings.json')
 $u=Join-Path $env:LOCALAPPDATA 'AutodeskMcpConnector';New-Item -ItemType Directory $u|Out-Null
 '{"notifications_enabled":false}'|Set-Content (Join-Path $u 'update-state.json')
 & $body
 if((Test-Path (Join-Path $state 'test-call.json')) -or $script:updates -ne 1){throw 'Disabled tasks re-enabled'}
 @{enabled=$true;day='Monday';time='10:00';additional_skill_roots=@('custom')}|ConvertTo-Json|Set-Content (Join-Path $state 'settings.json')
 & $body
 $call=Get-Content (Join-Path $state 'test-call.json') -Raw|ConvertFrom-Json
 if($call.day -ne 'Monday' -or $call.time -ne '10:00' -or $call.roots[0] -ne 'custom'){throw 'User settings lost'}
 'PASS: fresh integrated task setup; disabled preferences preserved; existing schedule and roots preserved'
}
finally {Remove-Item $testRoot -Recurse -Force}
