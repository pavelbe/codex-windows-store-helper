# Contributing

Start with a reproducible issue: Windows version, x64/Arm64, PowerShell version,
script and options, expected result, actual exit/error and whether the direct
or Store path was used. Redact account names, private paths and diagnostic logs.
For a vulnerability, follow [SECURITY.md](SECURITY.md).

Keep fixes small. The default installer lives in `scripts/Install-CodexDirect.ps1`;
the Store helpers share `scripts/CodexStore.Common.ps1`. Read their callers and
the tests before changing a contract. Do not use PowerShell automatic variable
names such as `$Host` for parameters; test through the existing call syntax.
Forward named PowerShell switches explicitly or with a hashtable; splatting an
array of switch-name strings passes positional values, unlike native CLI argv.
The Store entrypoint regressions cover each repair switch, both together and
the no-repair control without invoking real repair operations.

Run from the repository root in Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Smoke-Test.ps1
```

The suite mocks installation, signing and network boundaries. A passing test
does not prove installation, login, launch or Arm64 behavior on a real device.
For a regression, make the unchanged test fail on the old code first; name the
failure and include the final command/result in the PR.

Preserve user data and signature/identity checks. Do not add background updates,
automatic cleanup, credential access or GitHub Actions. The direct installer is
also vendored by HCA; its maintainer must synchronize that exact copy when it changes.
Do not redistribute OpenAI application binaries here.
