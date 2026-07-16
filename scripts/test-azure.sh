#!/usr/bin/env bash
# LOCAL DEVELOPMENT ONLY: smoke-test Azure OpenAI Responses API using project `.env`.
# Never use a maintainer/shared key from this path in a public build; see RELEASE.md.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import json, urllib.request, sys
from pathlib import Path

env = {}
for line in Path('.env').read_text().splitlines():
    line = line.strip()
    if not line or '=' not in line:
        continue
    k, v = line.split('=', 1)
    env[k.strip()] = v.strip()

uri = env['TARGET_URI']
key = env[env.get('defaultApiKeyEnv', 'API_KEY_GPT_5-4_Pro')] if 'defaultApiKeyEnv' in env else env['API_KEY_GPT_5-4_Pro']
model = env['AZURE_OPENAI_DEPLOYMENT_GPT_5-4_Mini']
body = json.dumps({
    "model": model,
    "input": [{"role": "user", "content": "[ACTION=casual] hey whats up"}],
    "stream": True,
    "max_output_tokens": 30,
}).encode()

req = urllib.request.Request(uri, data=body, headers={
    "Content-Type": "application/json",
    "api-key": key,
}, method="POST")

with urllib.request.urlopen(req, timeout=30) as r:
    out = []
    for raw in r:
        line = raw.decode().strip()
        if not line.startswith('data:'):
            continue
        payload = line[5:].strip()
        if payload == '[DONE]':
            break
        ev = json.loads(payload)
        if ev.get('type') == 'response.output_text.delta':
            out.append(ev.get('delta', ''))
    text = ''.join(out).strip()
    if not text:
        print('FAIL: empty stream')
        sys.exit(1)
    print('OK:', text)
PY
