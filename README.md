# SecureMsg — Privacy-first P2P Encrypted Messenger

Zero accounts. Zero servers for messages. Zero cost.
Identity = Curve25519 keypair. Everything encrypted with libsodium.

---

## Architecture summary

```
Flutter app (Android)
  ├── Identity     → Curve25519 keypair in Android Keystore
  ├── Crypto       → libsodium (XSalsa20-Poly1305 + Argon2id)
  ├── Storage      → Encrypted SQLite (drift + SQLCipher)
  ├── Network      → WebRTC P2P (data channel + VoIP)
  └── Signaling    → 3× Render.com free WS relay (round-robin)
                     TURN: metered.ca + Cloudflare + OpenRelay (random)
```

---

## Phase completion status

- [x] Phase 1 — Identity (keypair, base58, secure storage)
- [x] Phase 2 — Cryptography (messages, media, backup, integrity)
- [x] Phase 3 — Database (contacts, messages, media, outbox, backup)
- [x] Phase 4 — Signaling (multi-server pool, auto-reconnect)
- [x] Phase 5 — WebRTC P2P (data channel, VoIP, reconnect, registry)
- [x] Phase 6 — Messaging (send/receive/queue/ACK/disappearing/purge)
- [ ] Phase 7 — QR pairing UI
- [ ] Phase 8 — Chat UI
- [ ] Phase 9 — Media transfer
- [ ] Phase 10 — Backup UI
- [ ] Phase 11 — Settings (disappearing, WiFi-only, incognito)

---

## Prerequisites

```bash
Flutter SDK >= 3.19    # https://docs.flutter.dev/get-started/install
Dart >= 3.3
Android Studio + SDK (API 23+)
Node.js >= 18          # for signaling server
```

---

## Step 1 — Flutter setup

```bash
cd securemsg
flutter pub get
dart run build_runner build --delete-conflicting-outputs   # generate drift code
flutter run -d <your-android-device-or-emulator>
```

---

## Step 2 — Run signaling server locally (for testing)

```bash
cd signaling
npm install
node server.js
# Listening on ws://localhost:8080
```

In `lib/core/network/signaling_service.dart`, temporarily replace the pool with:
```dart
const _signalingPool = ['ws://10.0.2.2:8080']; // Android emulator → host
// or 'ws://192.168.x.x:8080' for physical device on same WiFi
```

---

## Step 3 — Deploy 3 signaling servers (production, free)

1. Create 3 GitHub accounts (or 3 repos on one account)
2. Push the `/signaling` folder to each repo
3. Go to [render.com](https://render.com) → create 3 free accounts (use email aliases)
4. New Web Service → connect each repo
   - Build command: `npm install`
   - Start command: `node server.js`
   - Plan: **Free**
5. Copy the 3 `.onrender.com` URLs into `_signalingPool` in `signaling_service.dart`

---

## Step 4 — Set up TURN servers (free, for NAT fallback)

### metered.ca (50 GB/month free)
1. Sign up at [metered.ca](https://www.metered.ca)
2. Dashboard → TURN credentials → copy username + credential
3. Paste into `_turnPool[0]` in `signaling_service.dart`

### Cloudflare Calls (1000 min/month free)
1. Sign up at [cloudflare.com](https://cloudflare.com)
2. Workers & Pages → Calls → TURN credentials
3. Paste into `_turnPool[1]`

### OpenRelay (unlimited community, backup)
- Already configured in `_turnPool[2]` — no signup needed

### Optional: Self-hosted on Oracle Cloud free tier (permanent)
```bash
# On Oracle Cloud free VM (Ubuntu 22.04):
sudo apt install coturn -y
sudo nano /etc/turnserver.conf
# Add: listening-port=3478, fingerprint, lt-cred-mech,
#       user=securemsg:YOUR_PASSWORD, realm=yourdomain.com
sudo systemctl enable --now coturn
```

---

## Step 5 — Test two-device pairing

```bash
# Device A
flutter run -d emulator-5554

# Device B  
flutter run -d emulator-5556

# Device A: tap "New contact" → QR appears
# Device B: tap "Scan" → scan QR
# → WebRTC handshake completes
# → Send test message — verify E2E encryption in debug output
```

---

## Cost breakdown at scale

| Users (active) | STUN | Signaling | TURN (20% fallback) | Total |
|---|---|---|---|---|
| 1,000 | Free | Free (Render) | ~2 GB → Free | **$0** |
| 10,000 | Free | Free (3× Render) | ~10 GB → Free | **$0** |
| 50,000 | Free | Free (3× Render) | ~50 GB → ~$5/mo | **~$5/mo** |

---

## Security properties

| Property | Mechanism |
|---|---|
| Message confidentiality | Curve25519 + XSalsa20-Poly1305 (libsodium) |
| Message authentication | Poly1305 MAC — tampering detected and rejected |
| Forward secrecy | NOT provided in v1 — add X3DH in v2 |
| Identity binding | Keypair in Android Keystore — no extraction |
| Storage encryption | SQLCipher AES-256 |
| Backup encryption | Argon2id key derivation + XSalsa20-Poly1305 |
| Transport | DTLS-SRTP (WebRTC spec, built-in) |

## Known limitations

- No forward secrecy in v1 (same keypair used for all messages)
- Signaling relay sees both pubkeys + connection timestamps (not content)
- Screenshot prevention: enforced on Android, detection-only on iOS
- No forwarding is UI-only — clipboard can be used
- Disappearing messages delete locally only; peer retains until their timer fires

---

## File structure

```
securemsg/
├── lib/
│   ├── main.dart
│   ├── core/
│   │   ├── identity/
│   │   │   └── identity_service.dart     ← Phase 1
│   │   ├── crypto/
│   │   │   └── crypto_service.dart       ← Phase 2
│   │   ├── storage/
│   │   │   └── database.dart             ← Phase 3
│   │   └── network/
│   │       ├── signaling_service.dart    ← Phase 4
│   │       ├── p2p_connection.dart       ← Phase 5
│   │       └── message_service.dart      ← Phase 6
│   ├── features/
│   │   ├── chat/                         ← Phase 7–8 (next)
│   │   ├── contacts/                     ← Phase 7
│   │   ├── calls/                        ← Phase 9
│   │   ├── media/                        ← Phase 9
│   │   └── settings/                     ← Phase 11
│   └── shared/
│       └── theme/app_theme.dart
├── signaling/
│   ├── server.js                         ← Deploy to Render.com ×3
│   ├── package.json
│   └── render.yaml
└── android/
    └── app/src/main/AndroidManifest.xml
```
