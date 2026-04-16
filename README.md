# Codex Windows Store Helper 🚀

Safe helper scripts for installing and updating the official Codex App for Windows through Microsoft Store / WinGet.

This repository does not contain Codex binaries, repacks, or extracted Store packages.

⭐ If this helper saved you time or helped you get Codex running, please star the repository.

## Why this exists 🧭

The official Windows install path for Codex is Microsoft Store / WinGet:

```powershell
winget install --id 9PLM9XGG6VKS --source msstore
```

In practice, some Windows machines fail earlier because of broken proxy settings or Microsoft Store state. These scripts wrap the official path and add repeatable diagnostics. 🛠️

## What is included 📦

- `scripts/Get-CodexStoreStatus.ps1`
  - Prints Codex, WinGet, Store, and proxy status.
  - Shows current local Codex version and package timestamps.
  - Shows recent Codex-related AppX/Store history.
- `scripts/Get-CodexAppDoctor.ps1`
  - Shows installed Codex version, OpenAI changelog metadata, Microsoft display catalog metadata, official Store page metadata, manifest metadata, official winget update verdict, and recent events.
- `scripts/Repair-StoreNetwork.ps1`
  - Reports current Store-related proxy state.
  - Can reset a broken loopback WinHTTP proxy.
  - Can run `wsreset.exe`.
- `scripts/Install-Codex.ps1`
  - Installs Codex from Microsoft Store through `winget`.
- `scripts/Update-Codex.ps1`
  - Updates Codex through the official Microsoft Store path.
  - Tries `winget upgrade` first.
  - If `winget upgrade` says `no updates`, but newer official Codex metadata already exists, it can fall back to `winget install --force`.
- `scripts/Reinstall-Codex.ps1`
  - Stops Codex, removes the current Appx package, clears LocalAppData package state, and reinstalls from the official Microsoft Store source.
  - Use this when Codex shows a black window, refuses to launch correctly, or an in-place update path is stuck.
- `tests/Smoke-Test.ps1`
  - Safe smoke test for the helper scripts.

## Requirements ✅

- Windows 11
- Microsoft Store
- `winget` from `Microsoft.DesktopAppInstaller`
- Windows PowerShell 5.1 or PowerShell 7

## Quick start ⚡

Open Windows PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-CodexStoreStatus.ps1
```

Check the last 7 days of Codex install/update history:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-CodexStoreStatus.ps1 -HistoryDays 7
```

Run the richer doctor report:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-CodexAppDoctor.ps1 -HistoryDays 7 -MaxHistoryEvents 12
```

Install Codex:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Codex.ps1
```

Install Codex with a safe proxy repair and Store cache reset first:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Install-Codex.ps1 -RepairBrokenLoopbackWinHttpProxy -ResetStoreCache
```

Update Codex:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Update-Codex.ps1
```

Update Codex with an explicit market for the display catalog check:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Update-Codex.ps1 -Market RU
```

Reinstall Codex when the app itself is broken:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-Codex.ps1 -Market RU
```

Preview what the reinstall script would clean up without making changes:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-Codex.ps1 -CheckOnly
```

If you do not see an obvious Updates menu in the Microsoft Store UI, the helper script above is the simplest way to run the official Store-backed update flow from PowerShell. On some machines `winget upgrade` still says `no updates` while the Store catalog is already newer; the helper can now detect that case and try the official `install --force` fallback. 🔎

If you want the closest thing to "what version is installed, what does the public Store metadata say, and does winget see anything newer?", run the doctor script. 🩺

## Troubleshooting 🧯

### `0x80072efd`

Common cause: broken WinHTTP proxy, especially loopback addresses such as `127.0.0.1:PORT` that are no longer listening.

Check status:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-CodexStoreStatus.ps1
```

Repair the broken loopback WinHTTP proxy and reset the Store cache:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Repair-StoreNetwork.ps1 -ResetBrokenLoopbackWinHttpProxy -ResetStoreCache
```

Then retry the official install path.

### Microsoft Store UI shows an error 🪟

The Store UI can still be flaky even when the backend install flow works. The scripts always use the official `winget + msstore` path.

### Codex opens to a black window ⬛

Use the dedicated reinstall path instead of repeating `winget install --force` over the same broken package state:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-Codex.ps1 -Market RU
```

Preview the cleanup plan first if you want a dry run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Reinstall-Codex.ps1 -CheckOnly
```

### `winget upgrade` says no updates, but you suspect a newer Codex build exists

This is a real pattern with the `msstore` source.

What helped in real machines:
- `HOME-PC`: repair broken Store / proxy state first, then let the Microsoft Store UI finish the update.
- `OFFICE-PC`: with healthy Store and clean `WinHTTP`, `winget install --force` succeeded even though `winget upgrade` still reported no updates.

The current `Update-Codex.ps1` script knows this pattern and can try the official `install --force` fallback when newer official metadata already exists.

## Smoke test 🧪

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Smoke-Test.ps1
```

## Notes 📝

- Store ID: `9PLM9XGG6VKS`
- Package family: `OpenAI.Codex_2p2nqsd0c76g0`
- The safest approach is to run the official Store install on the target machine.

## If it helped 💛

If this repo helped you install or update Codex on Windows, please consider leaving a star ⭐
