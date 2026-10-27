"""Attach only the fixed beta17 assets to its existing draft release."""
import hashlib
import json
import os
from pathlib import Path
import urllib.parse
import urllib.request

REPO = 'EhabHassan007/Autodesk-MCP-Releases'
TAG = 'v1.0.0-beta.17'
if os.environ.get('GITHUB_REPOSITORY') != REPO:
    raise SystemExit('Unexpected repository')
base = Path('release-candidates/beta17')
archive = base / 'Autodesk-MCP-Connector-1.0.0-beta.17.zip'
manifest = json.loads((base / 'latest.json').read_text())
if manifest['version'] != TAG[1:] or hashlib.sha256(archive.read_bytes()).hexdigest().upper() != manifest['sha256'].upper():
    raise SystemExit('Package verification failed')

def request(url, method='GET', data=None, mime='application/json'):
    parsed = urllib.parse.urlsplit(url)
    if parsed.scheme != 'https' or parsed.netloc not in ('api.github.com', 'uploads.github.com'):
        raise ValueError('Unexpected GitHub endpoint')
    req = urllib.request.Request(url, method=method, data=data, headers={
        'Authorization': 'Bearer ' + os.environ['GH_TOKEN'],
        'Accept': 'application/vnd.github+json', 'Content-Type': mime,
        'User-Agent': 'Autodesk-MCP-release-workflow',
    })
    with urllib.request.urlopen(req, timeout=60) as response:
        return json.load(response)

release = request(f'https://api.github.com/repos/{REPO}/releases/425817098')
if not release['draft'] or release['tag_name'] != TAG:
    raise SystemExit('Refusing to modify a published release')
assets = {item['name']: item for item in release['assets']}
for path, mime in [(archive, 'application/zip'), (base / 'latest.json', 'application/json')]:
    data = path.read_bytes()
    expected = 'sha256:' + hashlib.sha256(data).hexdigest()
    if path.name in assets:
        if assets[path.name].get('digest') != expected:
            raise SystemExit('Existing asset differs or lacks a verifiable digest: ' + path.name)
    else:
        url = f'https://uploads.github.com/repos/{REPO}/releases/{release["id"]}/assets?' + urllib.parse.urlencode({'name': path.name})
        asset = request(url, 'POST', data, mime)
        if asset.get('digest') != expected:
            raise SystemExit('Uploaded digest mismatch: ' + path.name)
    print('Verified draft asset:', path.name)
print('Release remains a draft; no notification channel was changed.')
