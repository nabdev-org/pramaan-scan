# Security

## Report a problem

Email contactus@neaurabuild.com with "Security: pramaan-scan" in the subject. Tell us:

- what you found and where, such as the file and line in this repository
- how to reproduce it
- the version or commit of the action you used

Please do not open a public issue for a security problem. We reply to say we have it, then again when we know what we will do about it.

Never send us a real upload key, token or private key. If you think a key has leaked, revoke it in Pramaan under Settings, Collectors first, then tell us.

## Supported versions

| Version | Supported |
|---|---|
| 1.x | Yes |

## What this action handles

- Your upload key, read from the `key` input. It is written to an owner-only file under `runner.temp` and removed when the step ends.
- The Pramaan collector, downloaded from your Pramaan and checked against a sha256 before it runs. See How the collector is checked in the README.
