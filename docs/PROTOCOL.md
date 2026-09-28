# SOSEXY / 啵啵贝 BLE protocol notes

These values were tested with one SOSEXY-advertising device. Hardware and
firmware variants may differ; always inspect the target device before assuming
compatibility.

## GATT

| Role | UUID |
|---|---|
| Service | `0000EE01-0000-1000-8000-00805F9B34FB` |
| Notify | `0000EE02-0000-1000-8000-00805F9B34FB` |
| Write with response | `0000EE03-0000-1000-8000-00805F9B34FB` |

Some devices do not advertise EE01, so the reference implementation scans and
filters by a local name beginning with `SOSEXY`, then verifies the GATT service
and characteristics after connection.

## Frame

Each command is 12 bytes:

```text
01 01 00 02 00 CC 11 LL 00 RR 11 01
```

- `LL`: level, clamped to decimal 0–100
- Motion: `CC=07`, `RR=08`
- Vibration: `CC=01`, `RR=02`
- Rotation: `CC=03`, `RR=04`

Send the three channel frames **serially** with write-with-response. Do not fire
parallel GATT writes.

## Keepalive and reconnect

- After the desired three-channel state is confirmed, repeat one current-state
  frame about every 400 ms.
- Do not repeat all three frames every tick; that adds unnecessary
  write-with-response contention.
- If a write receives no callback within 5 seconds, cancel/reconnect the BLE
  connection and rediscover the service/characteristics.
- Wait about 1 second between reconnect attempts.
- Preserve the latest desired state in the app, and only report success after
  CoreBluetooth confirms all requested writes.

## Remote control bridge

BLE remains local to the phone. A remote controller should send high-level
levels to the app through an authenticated HTTPS/WebSocket/SSE channel; the app
translates them to these BLE frames.

Recommended contract:

1. The user explicitly grants a control session in the foreground.
2. The server queues high-level commands, never arbitrary GATT bytes.
3. The app writes BLE packets and returns an execution acknowledgement.
4. A server timeout may end an HTTP request, but must not silently delete a
   durable queued command.
5. Stop/revoke must be immediately available, and control endpoints must never
   be exposed without authentication.
