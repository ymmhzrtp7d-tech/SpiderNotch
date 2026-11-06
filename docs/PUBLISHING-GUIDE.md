# Publishing SpiderNotch: a beginner's guide

This guide explains, in plain words, everything needed to offer SpiderNotch to
Mac and Windows users, with a website and automatic updates. You don't do it all
at once: each part says which phase of the plan it belongs to (see section 12 of
[ARCHITECTURE.md](ARCHITECTURE.md)), and we'll go through each one together.

## 1. The words you'll meet

| Word | What it means |
|---|---|
| **Build** | Turning the code into an app you can run. |
| **Code signing** | A digital signature on the app that proves who made it and that nobody changed it. Like a tamper-proof seal with your name on it. |
| **Certificate** | The ID card that makes your signature trusted. Apple issues the Mac one (Developer ID). On Windows it comes from a certificate company, or the Microsoft Store signs for you. |
| **Notarization** | Mac only. You send the signed app to Apple; a machine scans it for malware, usually within minutes, and gives it a "ticket". Macs then open it without warnings. |
| **Gatekeeper** | The Mac's guard that blocks apps that aren't signed and notarized, until the user allows them. |
| **SmartScreen** | Windows' guard that warns about unsigned or not-yet-known downloads. |
| **Installer / package** | The file people download: a `.dmg` on the Mac; a `Setup.exe` or a Store package on Windows. |
| **Release** | One published version, for example 1.3.0, with its files and notes. |
| **Hosting** | Computers on the internet that serve your website and files. |
| **Update feed** | A small file on the website listing the newest versions. The app reads it to know whether there's an update. Ours are signed, so a fake feed is rejected. |
| **Channel** | Stable (everyone) or Beta (people who opt in to try new things early). |
| **Repository (repo)** | The project folder with its full history, stored on GitHub. |
| **GitHub Actions** | GitHub's computers that build and test the code automatically whenever you upload changes. |

## 2. What you need, and what it costs

| | What it's for | Cost | When |
|---|---|---|---|
| **GitHub account** | Keeps the code, hosts the website (Pages) and the downloads (Releases), builds and tests (Actions) | Free | Phase 1 |
| **Apple Developer Program** | Developer ID certificate and notarization: Macs open SpiderNotch without warnings, and permissions survive updates | US$99/year | Phase 2 |
| **Password manager** | Safekeeping signing keys and passwords | Free options exist | Phase 2 |
| **Support email** | Where people write for help. A new address, not your personal one | Free | Phase 3 |
| **Domain name** (optional) | A nicer address such as `spidernotch.app` instead of `yourname.github.io/spidernotch` | About US$10–20/year | Decide before Phase 2 ends |
| **Windows PC or virtual machine** | Testing the Windows app | Free if you have a PC. On your Mac: UTM or VMware Fusion (both free) plus a Windows licence | Phase 4 |
| **Microsoft Store developer account** | Publishing on the Store, which signs the app for free (no SmartScreen warnings) | Free for individual developers | Phase 5 |
| **Windows code signing** (optional) | Removes the warning on the direct-download installer | See section 8 | Phase 5 or later |

**Minimum to start: US$0.** Recommended before inviting the public: the Apple
Developer Program (US$99/year). Everything else can stay free.

## 3. Public or private code?

GitHub's free plan only gives free website hosting and free build time to
**public** repositories, so this choice matters.

| | Public code | Private code |
|---|---|---|
| Who can see the code | Everyone | Only you and people you invite |
| Website and downloads | Free, in the same repo | Free, but in a second, public repo just for the website and downloads (downloads from a private repo need a GitHub login) |
| Automatic builds | Free | US$12 of build time a month included: about 1,200 minutes of Windows builds or 190 of Mac builds. Enough, since Mac releases are built on your Mac |
| Free Windows signing (SignPath Foundation) | Possible, with an open-source licence | No |

Public doesn't automatically mean open source: without a licence, people can read
the code but may not reuse it. With an open-source licence (MIT is the simplest),
anyone may reuse and change it. You already include a source zip in every
release, so a public repo fits what you're doing, but it's your choice.

## 4. Accounts you can create now

### GitHub (Phase 1)

1. Sign up at **github.com**. Your username appears in web addresses
   (`username.github.io`), so pick one you're happy to show.
2. Turn on two-factor authentication (Settings → Password and authentication).
3. Install **GitHub Desktop** (desktop.github.com). It uploads the project
   without typing Git commands.
4. Tell me your username and whether the code should be public. I'll prepare the
   repository; you'll add the SpiderNotch folder in GitHub Desktop and click
   **Publish repository**.

### Apple Developer Program (Phase 2)

1. You need an Apple Account with two-factor authentication turned on.
2. Enroll in the **Apple Developer** app or at
   **developer.apple.com/programs/enroll**.
3. Choose how you appear:
   - **Individual**: your legal name is shown as the developer (people can see it
     in the app's signature). Quickest.
   - **Organization** (to publish as a company name, such as "MTW"): needs a
     registered legal entity and a D-U-N-S number (free for Apple developers),
     and takes longer.
4. Pay US$99 (or the local price). Approval can take a day or two.

### Microsoft Store (Phase 5, no rush)

1. Go to **storedeveloper.microsoft.com** and sign up as an **Individual** with a
   Microsoft account.
2. Verify your identity (a government ID and a selfie). It's free for
   individuals.
3. When we get close to Phase 5, reserve the name "SpiderNotch" in Partner
   Center so nobody else takes it on the Store.

### Support email and web address (by the end of Phase 2)

- Make a separate email address for SpiderNotch with any free email service.
- Decide the web address: the free `username.github.io/spidernotch`, or your own
  domain bought from any domain registrar. Every copy of the app remembers where
  to look for updates, so this should be settled before the first public
  release with updates.

## 5. Mac: signing and notarization (Phase 2)

`Make Release.command` already knows how to do this. It only needs your
certificate and a saved notarization login.

1. **Create the Developer ID certificate** (once; no Xcode needed):
   1. Open **Keychain Access** → menu **Keychain Access → Certificate Assistant →
      Request a Certificate From a Certificate Authority…**. Enter your email and
      name, choose **Saved to disk**, and save the file.
   2. On developer.apple.com → Account → **Certificates** → **+** → **Developer ID
      Application** → upload that file (choose "G2 Sub-CA" if asked) → download
      the certificate.
   3. Double-click the downloaded file. It goes into your Keychain.
   4. Check it in Terminal:

      ```
      security find-identity -v -p codesigning
      ```

      It should list `Developer ID Application: Your Name (TEAMID)`.
2. **Save a notarization login** (once):
   1. At account.apple.com → Sign-In and Security → **App-Specific Passwords**,
      create one named "SpiderNotch notarization".
   2. In Terminal, with your email and your Team ID (developer.apple.com →
      Membership):

      ```
      xcrun notarytool store-credentials SpiderNotch --apple-id "you@example.com" --team-id "ABCDE12345"
      ```

      Paste the app-specific password when it asks.
3. **Back up the certificate**: in Keychain Access, find "Developer ID
   Application: …", right-click → **Export** → save as `.p12` with a strong
   password, and keep it in your password manager.
4. **Run `Make Release.command`**. It signs with your Developer ID, sends the app
   to Apple, attaches Apple's ticket and makes the .dmg. People can then open it
   without "Open Anyway".

Later in Phase 2 we add Sparkle (automatic updates). You'll run Sparkle's
`generate_keys` tool once: it creates the update key, keeps the private half in
your Keychain and prints the public half, which goes into the app. Then you'll
save a backup copy of the private key in your password manager.

## 6. The website (Phase 3)

GitHub Pages serves the `website/` folder for free, with HTTPS.

1. In the repo on github.com: **Settings → Pages → Build and deployment →
   Source: GitHub Actions**. Our workflow publishes the site.
2. The site appears at `https://username.github.io/spidernotch/`.
3. Own domain (optional): **Settings → Pages → Custom domain**. At your domain
   registrar, add the DNS records from GitHub's Pages guide (for `www`, a CNAME
   record pointing to `username.github.io`). Tick **Enforce HTTPS** once it's
   offered. Also verify the domain in your GitHub account settings, so nobody
   else can use it on GitHub.

I'll write the pages (listed in section 9 of ARCHITECTURE.md). You'll provide or
approve the screenshots and a short screen recording (⌘⇧5 on your Mac records the
screen).

## 7. The update "server" (Phases 2, 3 and 5)

There's no server program to run or pay for. "Update server" here just means
files at fixed web addresses:

| File | Where | What it is |
|---|---|---|
| `appcast.xml` | `…/updates/macos/` on the website | Mac: the list of versions (stable and beta), signed |
| Windows feed + signature | `…/updates/windows/` on the website | Windows direct download: versions and file hashes, signed |
| `latest.json` | The website | What the download page shows |
| `.dmg`, `.zip`, `Setup.exe`, update packages | GitHub Releases | The big files |

The app downloads the small signed feed, compares versions, fetches the big file
from GitHub Releases, and checks it against the feed before installing.

## 8. Windows: packaging and signing (Phase 5)

The same Windows build becomes two packages:

| | Microsoft Store (MSIX) | Direct download (Setup.exe) |
|---|---|---|
| Installing | From the Store app | Download from the website; no admin rights needed |
| Signing | Done by Microsoft, free | Yours, or none |
| Warning on first run | None | "Windows protected your PC" unless signed and known |
| Updates | Through the Store (our update window shows progress) | Velopack, from our signed feed |
| Beta channel | No, stable only | Yes |
| Publishing an update | Store review, usually a few days | Instant |

Ways to sign the direct download, cheapest first:

1. **Don't sign at first.** Fine for beta testers; the website explains
   **More info → Run anyway**.
2. **SignPath Foundation**: free for open-source projects that meet its rules.
   The signature then names "SignPath Foundation" as the publisher.
3. **Azure Artifact Signing**: US$9.99/month. Individuals must live in the US or
   Canada (organisations: US, Canada, EU or UK).
4. **A code-signing certificate** from a certificate company: about
   US$150–300+/year, kept on a hardware token or a cloud service.

None of these makes SmartScreen trust a brand-new app instantly; trust builds up
as people download it. The Store version avoids the problem completely, which is
why it's the main Windows download.

## 9. The release routine (once Phase 6 is done)

1. Write `shared/release-notes/1.4.0.md`: what's new, in plain words.
2. Set `VERSION` to `1.4.0-beta.1`.
3. Double-click **Make Release.command**. It builds and tests the Mac app, signs
   and notarizes it, and starts GitHub's Windows build. When both are ready, it
   shows you a draft release.
4. Check the draft and publish it to **Beta**. Beta testers get it within a day.
5. Try it yourself on Mac and Windows. Fix and repeat with `-beta.2` if needed.
6. Set `VERSION` to `1.4.0` and publish to **Stable**: the Mac update rolls out
   over about a week, the Store package goes to review, and the website and
   changelog update.
7. Keep an eye on the support email for a few days.

If something goes wrong: the release tool's **pull** command takes the version
out of the feeds and the download page, then you publish a fixed `1.4.1`.

## 10. Keep these safe (very important)

| Secret | Kept in | If you lose it |
|---|---|---|
| Developer ID certificate (`.p12` backup) | Keychain + password manager | Apple can issue a new one; existing copies keep working |
| Notarization app-specific password | Keychain | Make a new one |
| **Sparkle update key** | Keychain + password manager | Sparkle has a way to switch to a new key, but only while your Developer ID stays the same. Losing both means people must reinstall by hand |
| **Windows feed key** | Keychain + password manager | Direct-download users must reinstall by hand |
| Apple, Microsoft and GitHub logins | Password manager, with two-factor authentication | Account recovery |

Never put keys in the project folder, in Git, in email or in a chat (including
this one). The release tools read them from your Keychain.

## 11. Before every public release

Mac:

- [ ] Install from the .dmg on another user account or another Mac: no warning.
- [ ] Update from the previous version: settings, stickers and permissions kept.
- [ ] Beta switch on and off behaves as described.

Windows:

- [ ] Install from the Store and from `Setup.exe`, on Windows 11 and Windows 10.
- [ ] Two monitors with different scaling (for example 100% and 150%).
- [ ] Update from the previous version: data kept, What's New appears.

## 12. Further reading

- Sparkle (Mac updates): https://sparkle-project.org/documentation/
- Velopack (Windows installer and updates): https://docs.velopack.io/
- Apple Developer ID and notarization: https://developer.apple.com/developer-id/
- Free Microsoft Store registration for individuals:
  https://blogs.windows.com/windowsdeveloper/2025/09/10/free-developer-registration-for-individual-developers-on-microsoft-store/
- Azure Artifact Signing prices: https://azure.microsoft.com/pricing/details/artifact-signing/
- GitHub Pages: https://docs.github.com/en/pages
- GitHub Actions billing: https://docs.github.com/en/billing/concepts/product-billing/github-actions
