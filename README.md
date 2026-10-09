# Kryptex iOS Miner (sideload)

A personal iOS client that connects to the Kryptex Monero (XMR) pool
(`xmr-eu.kryptex.network:7029`, from the Kryptex APK). It is built for sideloading
onto your own iPhone with your Apple developer account, not for the App Store.

## Status

- Done: Stratum login and job receipt, background RandomX mining (`MiningWorker`),
  share submission, SwiftUI screen, silent-audio keep-alive, and the GitHub Actions
  signing and export workflow.
- RandomX is vendored in `ThirdParty/RandomX` (tevador/RandomX v1.2.1, see
  `UPSTREAM_COMMIT.txt`). It runs in light mode with the interpreter, because iOS
  does not allow the JIT for sideloaded apps. That is slow. Expect a low hashrate.
- Verified on Linux x86_64 (`tests/linux/run_tests.sh`, run in Docker with `swift:6.0`):
  the RandomX upstream known-answer vectors pass through both the C bridge and the
  Swift wrapper, target parsing passes, and worker shares recompute to the reported
  hashes.
- **Not verified:** the iOS arm64 build (needs Xcode), the GitHub Actions run (the
  workflow file is not pushed yet, because the `gh` token lacks the `workflow` scope),
  Stratum against the live pool, and anything on a device.
- The app code was written on Windows. `StratumClient`, `MinerController`, and the
  SwiftUI and AVFoundation files are not compiled anywhere yet.

## One-time Apple setup

1. In developer.apple.com, create an App ID that matches `PRODUCT_BUNDLE_IDENTIFIER`
   in `project.yml` and the `BUNDLE_ID` env in `.github/workflows/ios-sideload.yml`.
   Change both from `com.yourname.kryptexminer`.
2. Register your iPhone's UDID under Devices.
3. Create an **Apple Development** certificate. Export it with its private key as a `.p12`.
4. Create a **Development** provisioning profile for that App ID, your certificate, and your iPhone.

## GitHub secrets

Add these under the repo's Settings → Secrets and variables → Actions:

| Secret | Value |
| --- | --- |
| `IOS_P12_BASE64` | `base64` of the `.p12` file |
| `IOS_P12_PASSWORD` | Password you set on the `.p12` |
| `IOS_PROFILE_BASE64` | `base64` of the `.mobileprovision` file |
| `IOS_KEYCHAIN_PASSWORD` | Any random string |
| `IOS_TEAM_ID` | Your 10-character Team ID |

## Build and install

1. Run the **iOS sideload build** workflow manually (Actions tab → Run workflow).
2. Download the `KryptexMiner-ipa` artifact.
3. Install the IPA with Sideloadly (Windows) or Xcode (Mac).
4. On the iPhone: Settings → Privacy & Security → enable **Developer Mode**, then
   Settings → General → VPN & Device Management → trust your developer profile.
5. Open the app, enter your XMR wallet address, and tap Start.

## Notes

- The wallet address is stored only in the app's UserDefaults on the phone. Keep it out of the repo.
- Silent-audio keep-alive relies on the `audio` background mode. It is not App Store-approved.
  Expect iOS to suspend it under memory or thermal pressure.
- A phone produces a very small hashrate and runs hot on a charger. Expect little or no payout.
