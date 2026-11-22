# Google Play upload signing

The GitHub workflow builds both an APK and an AAB. The initial workflow is suitable for CI smoke builds and device testing. Before uploading the AAB to Google Play Console, configure a private upload keystore and wire it into the generated Android Gradle release signing configuration.

Recommended secrets:

- `ANDROID_KEYSTORE_BASE64` — base64-encoded `.jks` file
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

Never commit the keystore, `key.properties`, or passwords. Enable Google Play App Signing in Play Console. Keep a secure offline backup of the upload keystore.
