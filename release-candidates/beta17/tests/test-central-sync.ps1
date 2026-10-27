$ErrorActionPreference='Stop'
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('central-sync-'+[guid]::NewGuid().ToString('N'))
$env:LOCALAPPDATA=Join-Path $testRoot 'local'
$repo=Join-Path $testRoot 'repo';$state=Join-Path $testRoot 'state';$client=Join-Path $testRoot 'client'
New-Item -ItemType Directory $state,(Join-Path $repo '.agents/skills') -Force|Out-Null
. (Join-Path $PSScriptRoot '../source/runtime/scripts/central-skill-sync.ps1') -RepositoryRoot $repo -StateRoot $state -LibraryOnly
function Library($content){('{"commit":"abc","skills":[{"name":"revit-test","files":{"SKILL.md":'+($content|ConvertTo-Json -Compress)+'}}]}')|ConvertFrom-Json}
try{
 Install-ApprovedLibrary -Library (Library 'version one') -State $state -Repository $repo -ClientRoots @($client)
 $file=Join-Path $client 'revit-test/SKILL.md'
 if((Get-Content $file -Raw) -ne 'version one'){throw 'Approved skill missing'}
 Install-ApprovedLibrary -Library (Library 'version two') -State $state -Repository $repo -ClientRoots @($client)
 if((Get-Content $file -Raw) -ne 'version two'){throw 'Unmodified skill not updated'}
 Set-Content $file 'personal edits'
 Install-ApprovedLibrary -Library (Library 'version three') -State $state -Repository $repo -ClientRoots @($client)
 if((Get-Content $file -Raw).Trim() -ne 'personal edits'){throw 'Personal edits lost'}
 if((Get-Content (Join-Path $state 'approved-skills/revit-test/SKILL.md') -Raw) -ne 'version three'){throw 'MCP approved cache not updated'}
 $bad='{"name":"revit-test","files":{"SKILL.md":"ok","../escape.md":"bad"}}'|ConvertFrom-Json
 $failed=$false;try{Test-RemoteSkillFiles $bad}catch{$failed=$true}
 if(-not $failed){throw 'Approved path traversal accepted'}
 'PASS: approved skills installed and updated; local edits preserved; MCP cache refreshed; invalid path rejected'
}
finally{Remove-Item $testRoot -Recurse -Force}
