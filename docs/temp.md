## Merge Complete

**Done. Merged to main.**

```
main (HEAD)
├── 45376a6 chore: remove legacy F4 overlay and dead code
├── 44d1391 feat(ui): v22.0 Golden Parity + P7 Optimize Stage (62/62 tests)
└── f20d0cb fix(ui): dirty-gated rendering to eliminate perma-refresh flicker
```

**Cleanup completed:**
- Deleted `RenderStreamDetails.ps1`
- Deleted `test_stream_details_overlay.py`
- Updated F4 test → F2 only

**Final status:**
- 62/62 pre-ship sanity ✅
- 10/10 golden parity ✅
- 81 files, +31,546 / -10,483 lines

Ready for manual smoke (2 min): Launch → /go → /plan → F2 → ESC → resize.
