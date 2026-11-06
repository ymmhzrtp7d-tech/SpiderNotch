# Security policy

## Supported versions

Only the newest release gets fixes. SpiderNotch updates itself, so please make
sure you're on the latest version (spider menu → *Check for Updates…*).

## Reporting a problem

Please **don't** open a public issue for security problems. Instead use
GitHub's private reporting:
[Report a vulnerability](https://github.com/ymmhzrtp7d-tech/SpiderNotch/security/advisories/new).

You'll get a reply within a week. Once it's fixed, the release notes credit
you (unless you'd rather not).

## How updates are protected

- Every update archive is signed with an **EdDSA (ed25519) key**. The public
  half is built into the app (`SUPublicEDKey`); Sparkle refuses any download
  whose signature doesn't match, even if GitHub or the network were compromised.
- The private key is never in this repository. It lives in the maintainer's
  Keychain and in an encrypted GitHub Actions secret.
- When a Developer ID certificate is configured, releases are also signed by
  Apple's code signing and notarized by Apple.
