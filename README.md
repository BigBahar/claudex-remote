# Claudex Remote

The iPhone app for Claudex, Uri's desktop app that mixes Claude Code and Codex. It pairs with Claudex on the PC
(Settings → Phone, scan the QR code) and lets you follow and steer sessions from the phone.

This repository holds only the iPhone app, so its builds run on GitHub's free macOS runners. The desktop app
lives in a private repository. Builds are unsigned; Silo Store (a SideStore build) re-signs them on the phone.

Build: run the "iOS remote" workflow (Actions → iOS remote → Run workflow). It writes `claudex-remote.ipa`.
