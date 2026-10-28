"""Run Windows checks with bounded child processes and API-readable results."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--phase', choices=['regression', 'ui'], required=True)
phase = parser.parse_args().phase
base = Path('release-candidates/beta17').resolve()
engine = ['powershell.exe', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass']
checks = []
if phase == 'regression':
    for name in ['check-beta15', 'test-central-sync', 'test-central-preview', 'test-task-bootstrap', 'test-workflow-tools', 'test-beta15-upgrade']:
        command = engine + ['-File', str(base / 'tests' / (name + '.ps1'))]
        if name == 'test-beta15-upgrade':
            command += ['-PackagePath', str(base / 'Autodesk-MCP-Connector-1.0.0-beta.17.zip')]
        checks.append((name, command))
else:
    checks.append(('installer-smoke', engine + ['-STA', '-File', str(base / 'unpacked/Autodesk-MCP-Connector-1.0.0-beta.17/Support/Install-Autodesk-MCP-Connector.ps1'), '-SmokeTest']))

reports = []
failed = False
token = os.environ['GH_TOKEN']
child_env = dict(os.environ)
child_env.pop('GH_TOKEN', None)
for name, command in checks:
    print('Starting ' + name, flush=True)
    process = subprocess.Popen(command, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, env=child_env)
    try:
        output, _ = process.communicate(timeout=90)
        result = 'PASS' if process.returncode == 0 else 'FAIL'
    except subprocess.TimeoutExpired:
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
        output, _ = process.communicate(timeout=15)
        result = 'TIMEOUT'
    text = output.decode('utf-8', errors='replace').replace(token, '[redacted]')[-6000:]
    failed |= result != 'PASS'
    reports.append(f'### {name}: {result}\n```text\n{text}\n```')
    print(name + ': ' + result + '\n' + text, flush=True)

payload = {'name': 'Beta17 Windows ' + phase, 'head_sha': os.environ['GITHUB_SHA'],
           'status': 'completed', 'conclusion': 'failure' if failed else 'success',
           'output': {'title': 'Windows checks: ' + ('failed' if failed else 'passed'),
                      'summary': '\n\n'.join(reports)}}
request = urllib.request.Request('https://api.github.com/repos/EhabHassan007/Autodesk-MCP-Releases/check-runs',
    method='POST', data=json.dumps(payload).encode(), headers={
        'Authorization': 'Bearer ' + token, 'Accept': 'application/vnd.github+json',
        'Content-Type': 'application/json', 'User-Agent': 'Autodesk-MCP-checks'})
with urllib.request.urlopen(request, timeout=30) as response:
    assert response.status == 201
raise SystemExit(1 if failed else 0)
