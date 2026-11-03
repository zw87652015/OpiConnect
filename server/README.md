# OpiConnect push relay

APNs push relay for OpiConnect (deployed behind `https://push.luojiajiang.uk/opi/*`).

Flow: the watch app gets an APNs device token → registers it here under `pairId`+`secret` →
the Android app posts sealed ciphertext to `/v1/push` → the service signs an APNs JWT and
forwards it over HTTP/2. The relay never sees plaintext, `encKey`, or the master key.
See `docs/PROTOCOL.md` for the wire spec.

Single file, Node 22 built-ins only, no npm dependencies. `server/test.mjs` is a self-contained
test suite (spawns the server against a local APNs stub):

```sh
node --check server/index.mjs
node --test server/test.mjs
```

## Environment variables

| Variable | Required | Description |
| --- | --- | --- |
| `APNS_KEY_FILE` | yes | path to the `.p8` private key |
| `APNS_KEY_ID` | yes | Key ID of that key |
| `APNS_TEAM_ID` | yes | Apple Developer Team ID |
| `APNS_TOPIC` | yes | watch app bundle id, e.g. `<prefix>.opiconnect.watchkitapp` |
| `DATA_DIR` | yes | directory holding `pairings.json` |
| `APNS_ENV` | no | default `production`; clients can override per registration |
| `PORT` | no | default `8788` |
| `HOST` | no | default `127.0.0.1` (served behind Caddy) |
| `APNS_URL` | no | test only: use one base URL for all envs (e.g. an h2c stub) |

Missing required variables cause an immediate exit at startup.

## Deployment

The server already runs the remote-agent push service at `push.luojiajiang.uk` (systemd unit
`remote-agent-push`, files in `/opt/remote-agent-push`, APNs key at
`/opt/remote-agent-push/AuthKey.p8`, proxied by Caddy). OpiConnect is a second, independent
instance on the same machine: same key, same domain, different path and port.

### 1. Apple Developer portal (developer.apple.com → Account)

1. **Confirm the Team ID**: Membership page → "Team ID" (10 characters). It must be the same
   team that issued the existing `.p8` key.
2. **Register App IDs** (Certificates, Identifiers & Profiles → Identifiers → `+` → App IDs):
   - `<prefix>.opiconnect.watchkitapp` — capabilities: **Push Notifications**, **App Groups**
   - `<prefix>.opiconnect.watchkitapp.NotificationService` — capability: **App Groups**
3. **Register the App Group** (Identifiers → App Groups → `+`):
   `group.<prefix>.opiconnect`, then enable it on both App IDs above.
4. **APNs key** (Keys page): one `.p8` key works for **all apps in the team**, so the key
   already used by the remote-agent push service can be reused — check that its entry shows
   "Apple Push Notifications service (APNs)" enabled and copy its **Key ID**. If you can't
   confirm or want a separate key: `+` → check "Apple Push Notifications service" → Register →
   **Download** (the file is shown only once).

### 2. Ubuntu: Node, user, files

```sh
node -v   # must be >= 22
# If not, install via NodeSource:
#   curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
#   sudo apt-get install -y nodejs

sudo useradd --system --home /opt/opiconnect-push opipush
sudo install -d -o opipush -g opipush /opt/opiconnect-push/app /opt/opiconnect-push/data
```

Copy the app from your Mac:

```sh
scp server/index.mjs user@your-server:/tmp/index.mjs
# on the server:
sudo install -o opipush -g opipush /tmp/index.mjs /opt/opiconnect-push/app/index.mjs
```

Reuse the existing APNs key:

```sh
sudo cp /opt/remote-agent-push/AuthKey.p8 /opt/opiconnect-push/AuthKey.p8
sudo chown opipush /opt/opiconnect-push/AuthKey.p8
sudo chmod 600 /opt/opiconnect-push/AuthKey.p8
```

### 3. Env file

`/opt/opiconnect-push/env` (owned by `opipush`, mode `600`):

```sh
PORT=8788
HOST=127.0.0.1
APNS_KEY_FILE=/opt/opiconnect-push/AuthKey.p8
APNS_KEY_ID=XXXXXXXXXX          # Key ID from the Apple portal
APNS_TEAM_ID=XXXXXXXXXX         # Team ID from the Membership page
APNS_TOPIC=<prefix>.opiconnect.watchkitapp
APNS_ENV=production
DATA_DIR=/opt/opiconnect-push/data
```

`APNS_ENV` is only the **default**: the watch sends `env` on every registration, and Xcode
debug builds installed directly use **sandbox** tokens while TestFlight/App Store builds use
**production** — so one service handles both.

### 4. systemd unit

`/etc/systemd/system/opiconnect-push.service`:

```
[Unit]
Description=OpiConnect push service
After=network-online.target
Wants=network-online.target

[Service]
User=opipush
WorkingDirectory=/opt/opiconnect-push/app
EnvironmentFile=/opt/opiconnect-push/env
ExecStart=/usr/bin/node index.mjs
Restart=always
RestartSec=3
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=/opt/opiconnect-push/data
PrivateTmp=true

[Install]
WantedBy=multi-user.target
```

```sh
sudo systemctl daemon-reload && sudo systemctl enable --now opiconnect-push
curl http://127.0.0.1:8788/healthz    # -> ok
journalctl -u opiconnect-push -f
```

### 5. Caddy

Edit `/etc/caddy/Caddyfile`: inside the existing `push.luojiajiang.uk { ... }` block, add a
`handle_path /opi/*` route **before** the existing `reverse_proxy`. Because `handle`/`handle_path`
directives are mutually exclusive groups, wrap the existing proxy in a `handle` block.

Before:

```
push.luojiajiang.uk {
    reverse_proxy 127.0.0.1:8787
}
```

After:

```
push.luojiajiang.uk {
    handle_path /opi/* {
        reverse_proxy 127.0.0.1:8788
    }
    handle {
        reverse_proxy 127.0.0.1:8787
    }
}
```

`handle_path` strips the `/opi` prefix, so `https://push.luojiajiang.uk/opi/healthz` reaches
this service as `/healthz`.

Validate and reload:

```sh
sudo caddy validate --config /etc/caddy/Caddyfile
sudo systemctl reload caddy
```

Verify **both** services:

```sh
curl https://push.luojiajiang.uk/opi/healthz   # -> ok  (new)
curl https://push.luojiajiang.uk/healthz       # -> ok  (existing remote-agent, unchanged)
```

### 6. Logs and updates

```sh
journalctl -u opiconnect-push -f          # logs
journalctl -u opiconnect-push --since today
```

To update: copy the new `index.mjs` over `/opt/opiconnect-push/app/index.mjs` (ownership
`opipush:opipush`), then `sudo systemctl restart opiconnect-push`. Pairings persist in
`/opt/opiconnect-push/data/pairings.json` across restarts.

## API reference

Base URL: `https://push.luojiajiang.uk/opi` (or `http://127.0.0.1:8788` directly).
All POST bodies are JSON, max 8 KB. Errors: `{"error":"<message>"}`. `GET /healthz` → `ok`.

| Endpoint | Body | Result |
| --- | --- | --- |
| `POST /v1/register` | `{pairId, secret, token, env?}` | `200 {ok:true}` — first registration for a `pairId` is trusted; later ones must match the stored `sha256(secret)` (else `401`). `env`: `production`\|`sandbox`, default `APNS_ENV`. |
| `POST /v1/push` | `{pairId, secret, kind, id, c}` | `kind`: `alert` (priority 10, `mutable-content`, `apns-collapse-id=id`) or `remove` (background, priority 5). `c` = base64url sealed payload, ≤3000 chars. `404` unknown pairId, `401` wrong secret, `410` token dead (pairing deleted), `502` other APNs error. |
| `POST /v1/unregister` | `{pairId, secret}` | Deletes the pairing; `200 {ok:true}` (idempotent). |

Rate limits: register 20/hour/IP, push 120/min/pairId, 600/min/IP overall.
Logs never contain `c`, tokens, or secrets.

## Troubleshooting

| Symptom | Meaning / fix |
| --- | --- |
| `404 {"error":"not registered"}` on `/v1/push` | The watch never registered (or its pairing was deleted after a dead token). Re-register from the watch app. |
| `401 {"error":"invalid secret"}` | `secret` doesn't match the one stored at first registration — wrong QR/master key, or the pairing was hijacked. Re-pair. |
| `410 {"error":"gone"}` | APNs says the device token is dead (`BadDeviceToken`/`DeviceTokenNotForTopic` or `410`); the pairing was deleted. The watch must re-register. |
| `403` in logs, reason `InvalidProviderToken` | Wrong `APNS_KEY_ID` or `APNS_TEAM_ID`, or the `.p8` file doesn't match the Key ID. |
| `DeviceTokenNotForTopic` | `APNS_TOPIC` doesn't match the watch app's bundle id. |
| `BadDeviceToken` | Environment mismatch: a sandbox token was sent to production or vice versa (check the `env` sent at registration vs. `APNS_ENV`). |
| `502` with another reason | Any other APNs error; the reason string is returned to the caller and logged. |
| `curl` to `/opi/healthz` returns 404 from Caddy | `handle_path` not reloaded or placed after a catch-all route — check `caddy validate` output and block order. |
