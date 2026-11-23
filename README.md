# Wallpaper Desk

Wallpaper Desk is an independent Windows utility for setting a local image behind the chat content of the Microsoft Store edition of OpenAI Codex. It includes an opacity slider and optional per-image color extraction for the accent, surface, and foreground.

## Getting started

1. Install the Microsoft Store edition of Codex.
2. Install Python 3.11 or later and ensure it is on PATH. Run `python -m pip install -r requirements.txt` for image color extraction.
3. Download and fully extract the ZIP. Double-click `Open-WallpaperDesk.vbs` to open the control panel.
4. Choose an image, set its opacity, then click **保存并应用** (Save and apply). The control panel supports PNG, JPEG, and WebP up to 12 MB.
5. For your first themed session, fully quit ordinary Codex and click **启动带主题的 Codex** (Launch themed Codex). To launch directly later, run `wscript.exe Open-WallpaperDesk.vbs start` from the extracted directory.

The control panel is currently in Chinese. At 0% opacity the wallpaper is hidden. At 100% the image is painted at full strength. **恢复默认壁纸** restores the bundled artwork. Local image selections, opacity, and status logs are stored under `%LOCALAPPDATA%\WallpaperDesk`.

## Compatibility and local debugging

The launcher starts the signed Store app with an ephemeral, loopback-only Chromium debugging port. Other processes on the same computer may be able to connect while that session is running. Quit themed Codex to close the port. The tool checks the Windows listener's process ID and loopback address before connecting. Renderer styling may need adjustment after an app update. The app installation is never patched. Choosing or restoring an image also updates the three color fields of the current native appearance mode when the local TOML format is supported.

Run the local checks in Windows PowerShell:

```powershell
powershell.exe -NoProfile -STA -File .\Start-CodexWallpaper.ps1 -SelfTest
powershell.exe -NoProfile -STA -File .\Start-CodexWallpaper.ps1 -SelfTest -ManageWallpaper
```

## Rights

Wallpaper Desk is an unofficial project with no affiliation or endorsement from OpenAI. Codex and OpenAI are referenced solely to identify compatibility. This package distributes project source and one original, procedurally generated abstract background. The generation script is included. Users supply their own replacement images and are responsible for any rights required to redistribute them.

Code and the bundled original abstract wallpaper are provided under the MIT license. See [LICENSE](LICENSE).
