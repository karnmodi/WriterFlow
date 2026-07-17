# Packaging assets

Source artwork and generators for the macOS app icon and the DMG installer window.

| Path | Purpose |
|------|---------|
| `AppIcon.icns` | App / volume icon bundled into `WriterFlow.app` and the DMG |
| `dmg/background.png` | Finder DMG window background (720×460) |
| `dmg/background@2x.png` | Retina companion art |
| `generate-assets.py` | Regenerates the files above from the brand mark |

## Regenerate

```bash
python3 packaging/generate-assets.py
```

Requires Pillow (`pip3 install pillow`) plus macOS `iconutil` / `sips`.

## DMG installer window

`scripts/make-dmg.sh` builds a read-write disk image, copies the app and an
`Applications` symlink, applies the background via Finder AppleScript (icon
positions + window bounds → `.DS_Store`), then compresses to UDZO.

When a user double-clicks the downloaded DMG, macOS mounts the volume and
Finder opens this window automatically — the standard Mac drag-to-Applications
install flow.
