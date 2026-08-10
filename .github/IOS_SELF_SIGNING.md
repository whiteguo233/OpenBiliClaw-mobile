# iOS unsigned IPA self-signing

`OpenBiliClaw-iOS-unsigned-vX.Y.Z.ipa` is intentionally unsigned and cannot be installed directly.

1. Download the IPA and verify it against the release SHA-256 checksum or GitHub artifact attestation.
2. Use a trusted local signing tool with your own Apple ID, signing certificate, and provisioning profile.
3. If your Apple account cannot use `com.openbiliclaw.openbiliclawApp`, replace it with a Bundle ID that belongs to your account.
4. Sign the main app and every embedded framework, then install the resulting signed IPA on a device allowed by your provisioning profile.

The signature lifetime, device allowance, entitlements, and installation method are controlled by your Apple account and profile. Never send Apple credentials or private signing keys to this repository or to an untrusted signing service.
