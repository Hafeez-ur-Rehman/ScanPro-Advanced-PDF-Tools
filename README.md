# ScanPro — Cross-platform Document Scanner

ScanPro is a starter product repository with two clients:

- **Android/iOS:** Flutter app in `lib/` with native document scanning (ML Kit on Android / VisionKit on iOS through `doc_scan_flutter`), multi-page capture, app-private local image storage, PDF export and English on-device OCR.
- **Web/PWA:** browser app in `web/` (camera capture, multi-image import, crop/rotate, image enhancement, IndexedDB local library, English OCR, PDF export, PDF merge, backup/restore and installable offline shell).

The web app is deployed separately through GitHub Pages. The Flutter mobile app is built through GitHub Actions.

> This is an independent scanner project and is not affiliated with CamScanner. It is a feature-rich development build, not yet feature-equivalent to CamScanner. Cloud backup now has Firebase email/password authentication, private per-user Storage uploads, Firestore metadata and restore flows for the Flutter app and Web/PWA. Firebase project setup and security-rule deployment are required before cloud features can be used. Advanced PDF tools, conflict handling, account deletion and store signing still require additional work.

## 1. Upload to GitHub

1. Extract the ZIP.
2. Create a new GitHub repository.
3. Upload the **contents** of this folder to the repository root (not the containing folder itself).
4. Set the default branch to `main`.

## 2. Build Android APK and AAB

1. Open the repository's **Actions** tab.
2. Select **Android APK and Play Store AAB**.
3. Click **Run workflow**.
4. When the workflow completes, open the run and download `scanpro-android-release` from Artifacts.

The artifact contains:
- `app-release.apk` — install/test on Android devices.
- `app-release.aab` — Android App Bundle build output.

The starter workflow uses Flutter's default debug-signing fallback until you configure a private Play upload keystore. Google Play production publishing requires an AAB signed with your own upload key. Never commit keystore files or passwords; add signing support through GitHub Actions Secrets before publishing.

## 3. Deploy the web app

1. In GitHub, open **Settings → Pages**.
2. Set **Build and deployment → Source** to **GitHub Actions**.
3. Push to `main` or manually run **Deploy ScanPro Web App to GitHub Pages**.
4. Open the Pages URL shown in the workflow deployment.

The web scanner needs HTTPS for camera access. The app shell is cached for repeat visits; OCR and PDF libraries are loaded from CDNs and therefore need internet access the first time.

## 4. Build iOS

Run **iOS unsigned build** in Actions. It produces an unsigned `Runner.app` archive for testing/inspection. Publishing to TestFlight or the App Store requires Apple Developer signing certificates, provisioning profiles and App Store Connect setup. GitHub Actions does not bypass Apple's signing requirements.

## Current feature status

| Capability | Web/PWA | Flutter mobile |
|---|---:|---:|
| Camera capture / gallery import | Yes | Yes |
| Native automatic edge detection and perspective correction | Browser camera + manual crop | Yes, via native scanner SDK |
| Multi-page scan session | Yes | Yes |
| Crop and rotate | Yes | Yes (native scanner flow / cropper) |
| Basic image enhancement filters | Yes | Native scanner enhancement |
| English OCR | Yes (Tesseract.js; internet needed initially) | Yes (on-device ML Kit) |
| Create multi-page PDF | Yes | Yes |
| Merge existing PDFs | Yes | Not yet |
| Local document library | Yes (IndexedDB) | Local PDF library + share |
| Export/restore local backup | Yes | Not yet |
| Cloud backup / restore | Yes (Firebase setup required) | Yes (Firebase setup required) |

## Cloud backup

Firebase email/password sign-in, user-scoped Storage uploads, Firestore document metadata, and restore are implemented for Flutter mobile and Web/PWA. Follow `FIREBASE_SETUP.md` to create the Firebase project, enable Email/Password Authentication, deploy the included rules, and add GitHub Actions secrets. Cloud backup is user-initiated; scans remain local until the user signs in and starts a backup. Conflict handling, cloud deletion propagation, password reset and account deletion remain future work. Never use public read/write rules.

## Firebase cloud setup

See [`FIREBASE_SETUP.md`](FIREBASE_SETUP.md) for Firebase Console setup, GitHub Secrets, and security rules.

## Privacy notes

- Web scans are stored in IndexedDB in the current browser profile.
- Browser OCR uses Tesseract.js and downloads the English recognition data when first used.
- Camera access requires user permission and a secure HTTPS origin.
- Exported JSON backups contain document images. Treat them as sensitive files.


## Advanced PDF tools (mobile)

The mobile app now includes PDF merge, split-into-single-page-files, optimization, password protection, a visible handwritten signature, and local document folders. The Web/PWA tools also include merge, split-to-ZIP, basic PDF optimization, and visible first-page signature placement. Select PDFs from the device file picker. The signature is a visible mark only, not a certificate-backed digital signature. Syncfusion Flutter PDF is used for advanced mobile PDF editing/security; review and comply with its Community or commercial licensing terms before production distribution. The Web/PWA currently does not provide PDF password encryption.
