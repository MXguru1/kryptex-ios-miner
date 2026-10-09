# Kryptex iOS Miner (sideload)

A personal iOS client that connects to the Kryptex Monero (XMR) pool
(`xmr-eu.kryptex.network:7029`, from the Kryptex APK). It is built for sideloading
onto your own iPhone with your Apple developer account, not for the App Store.

## Status

- Done: Stratum login, job receipt, share submission interface, SwiftUI screen,
  silent-audio keep-alive, and the GitHub Actions signing and export workflow.
- **Not done: RandomX hashing.** `Sources/App/RandomXEngine.swift` is a placeholder
  (`isLinked == false`). The app connects and shows jobs but does not hash, so it
  earns nothing until a RandomX library for arm64 is linked.
- Not compiled or tested on a device yet. The code was written on Windows.

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
