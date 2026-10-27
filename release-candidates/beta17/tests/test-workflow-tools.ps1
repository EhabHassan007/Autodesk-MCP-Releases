$ErrorActionPreference='Stop'
$previousLocalAppData = $env:LOCALAPPDATA
$testLocalAppData = Join-Path ([IO.Path]::GetTempPath()) ('workflow-test-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory $testLocalAppData -Force | Out-Null
$env:LOCALAPPDATA = $testLocalAppData
try {
. (Join-Path $PSScriptRoot '../source/runtime/src/autodesk/autodesk-bridge.ps1') -LibraryOnly
function Call($name,$arguments) {
 Invoke-AutodeskMcpRequest ([pscustomobject]@{id=1;method='tools/call';params=[pscustomobject]@{name=$name;arguments=$arguments}})
}
$r=Call 'list_skill_workflows' @{}
$d=$r.result.content[0].text|ConvertFrom-Json
if($r.result.isError -or $d.skills.Count -ne 27){throw 'Skill inventory mismatch'}
$r=Call 'read_skill_workflow' @{name='revit-read-write'}
$d=$r.result.content[0].text|ConvertFrom-Json
if($r.result.isError -or $d.content -notmatch 'document_info'){throw 'Cannot read workflow'}
foreach($file in @('../VERSION','/etc/passwd','C:\Windows\win.ini','references/../../VERSION')){
 $r=Call 'read_skill_workflow' @{name='revit-read-write';file=$file}
 if(-not $r.result.isError){throw "Path escape accepted: $file"}
}
'PASS: 27 workflow entries available over MCP; workflow content readable; path traversal rejected'

} finally {
 $env:LOCALAPPDATA = $previousLocalAppData
 Remove-Item $testLocalAppData -Recurse -Force
}
