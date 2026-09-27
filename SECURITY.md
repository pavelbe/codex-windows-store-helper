# Security

Do not include credentials, account/session files, full diagnostic logs or
personal paths in a public issue. Share the smallest redacted reproduction.

For a vulnerability, use GitHub's private **Report a vulnerability** option if
it is available. Otherwise open a minimal issue asking the maintainer for a
private reporting channel, without exploit details or sensitive attachments.
Do not assume private reporting is enabled.

The direct installer validates Windows signature trust, package identity,
architecture and OS compatibility before deployment. Do not bypass these
checks, import an untrusted certificate or disable Windows security to make an
installation succeed. Report signature failures with the package SHA256 and
redacted error instead of uploading the package or local account data.
