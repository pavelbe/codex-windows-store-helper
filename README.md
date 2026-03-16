# Codex Windows Store Helper

Safe helper scripts for installing and updating the official Codex App for Windows through Microsoft Store / WinGet.

This repository does not contain Codex binaries, repacks, or extracted Store packages.

## Why this exists

The official Windows install path for Codex is Microsoft Store / WinGet:

```powershell
winget install --id 9PLM9XGG6VKS --source msstore
```

In practice, some Windows machines fail earlier because of broken proxy settings or Microsoft Store state. These scripts wrap the official path and add repeatable diagnostics.

## What is included

- `scripts/Get-CodexStoreStatus.ps1`
  - Prints Codex, WinGet, Store, and proxy status.
- `scripts/Repair-StoreNetwork.ps1`
  - Reports current Store-related proxy state.
  - Can reset a broken loopback WinHTTP proxy.
  - Can run `wsreset.exe`.
- `scripts/Install-Codex.ps1`
  - Installs Codex from Microsoft Store through `winget`.
- `scripts/Update-Codex.ps1`
  - Updates Codex through `winget`, or installs it if missing.
- `tests/Smoke-Test.ps1`
  - Safe smoke test for the helper scripts.

## Requirements

- Windows 11
- Microsoft Store
- `winget` from `Microsoft.DesktopAppInstaller`
- Windows PowerShell 5.1 or PowerShell 7

## Quick start

Open Windows PowerShell and run:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\Get-CodexStoreStatus.ps1
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

## Troubleshooting

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

### Microsoft Store UI shows an error

The Store UI can still be flaky even when the backend install flow works. The scripts always use the official `winget + msstore` path.

## Smoke test

```powershell
powershell -ExecutionPolicy Bypass -File .\tests\Smoke-Test.ps1
```

## Notes

- Store ID: `9PLM9XGG6VKS`
- Package family: `OpenAI.Codex_2p2nqsd0c76g0`
- The safest approach is to run the official Store install on the target machine.
