$ErrorActionPreference='Stop'
$t=Join-Path ([IO.Path]::GetTempPath()) ('central-preview-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $t 'local';$env:USERPROFILE=Join-Path $t 'user'
$repo=Join-Path $t 'repo';$state=Join-Path $t 'state';$extra=Join-Path $t 'extra'
New-Item -ItemType Directory (Join-Path $repo '.agents/skills'),(Join-Path $extra 'demo') -Force|Out-Null
[IO.File]::WriteAllText((Join-Path $extra 'demo/SKILL.md'),"---`nname: demo`ndescription: demo workflow`n---`nInspect a blank test document.")
try{
 $out=@(& (Join-Path $PSScriptRoot '../source/runtime/scripts/weekly-skill-collection.ps1') -Action Preview -RepositoryRoot $repo -StateRoot $state -AdditionalSkillRoots @($extra))
 $result=Get-Content (Join-Path $state 'last-result.json') -Raw|ConvertFrom-Json
 if($result.status -ne 'completed' -or $result.details -notmatch 'demo'){throw 'Central preview did not collect the custom skill'}
 if(Test-Path (Join-Path $state 'service.json')){throw 'Preview created a device credential'}
 'PASS: scheduled runner invokes central preview without Git, network, or enrollment'
}
finally{Remove-Item $t -Recurse -Force}
