# ScanPro Firebase setup (Cloud Backup)

Cloud backup is optional. The app remains usable offline without Firebase. Cloud sync is user-initiated: nothing uploads until the user signs in and presses Backup.

## 1. Create a Firebase project

1. Open https://console.firebase.google.com/ and create a project.
2. Add Android, iOS and Web apps to the same Firebase project.
3. Use the Android application ID `com.scanpro.app` (or update the Android registration if you change the application ID).
4. Enable **Authentication → Sign-in method → Email/Password**.
5. Create a **Cloud Firestore** database.
6. Enable **Cloud Storage** and select a bucket.
7. In Firebase Console, publish the rules from `firebase/firestore.rules` and `firebase/storage.rules`. You can also deploy them with Firebase CLI using `firebase deploy --only firestore:rules,storage` after `firebase login` and `firebase use <project-id>`.

Never use public read/write rules. The supplied rules restrict each document to the authenticated owner's `users/{uid}` namespace.

## 2. Configure Android and iOS GitHub builds

In the GitHub repository, open **Settings → Secrets and variables → Actions → New repository secret** and add:

| Secret name | Firebase value |
|---|---|
| `FIREBASE_API_KEY` | Web API key from Project settings → General |
| `FIREBASE_PROJECT_ID` | Project ID |
| `FIREBASE_MESSAGING_SENDER_ID` | Sender ID |
| `FIREBASE_STORAGE_BUCKET` | Default Storage bucket name |
| `FIREBASE_ANDROID_APP_ID` | App ID for the Android app |
| `FIREBASE_IOS_APP_ID` | App ID for the iOS app |
| `FIREBASE_WEB_APP_ID` | App ID for the Web app |
| `FIREBASE_AUTH_DOMAIN` | Auth domain, commonly `<project-id>.firebaseapp.com` |

The Android and iOS GitHub Actions workflows pass these values as Dart compile-time definitions. Firebase client configuration is not a server secret; Firestore and Storage rules provide access control. Do not put service-account private keys in the client app.

If these secrets are not present, the mobile app still works offline and cloud features show a setup message.

## 3. Configure the Web/PWA app

1. Open the GitHub Pages website over HTTPS.
2. Go to **Settings & backup**.
3. Paste the Firebase Web app configuration JSON from Project settings → Your apps → Web app.
4. Enter an email and password, then choose **Create account** or **Sign in**.
5. Use **Back up all documents** or **Restore cloud documents**. The web client loads Firebase's modular SDK from Google's CDN, so the first cloud connection needs internet access.

Web documents are stored in the browser's IndexedDB until the user explicitly starts a cloud backup. The Web app uses the same user-scoped Firestore/Storage rules as mobile.

## 4. Important release and privacy notes

- Cloud backups contain scanned document images and OCR text may be included in Web backup JSON. Treat this data as sensitive.
- Users must explicitly opt in by signing in and pressing the backup action.
- Deleting a local document does not currently delete its cloud copy, and cloud deletion propagation is not implemented.
- Cloud restore currently restores all cloud records into the local library; advanced conflict resolution and selective restore are future work.
- Email/password account deletion, password reset UI, and account export/deletion workflows still need product work before a public launch.
- Add a privacy policy and complete Google Play Data safety / Apple privacy disclosures before publishing.
- Google Play requires an AAB signed with your own upload key. Configure signing separately; never commit keystores or passwords.

## 5. Current cross-platform restore behavior

The same Firebase project and account can be used by all clients, but this iteration keeps backup payloads tagged by client format (`pdf` for Flutter mobile and `web-json` for the PWA). Each client lists and restores its own payload type. A universal cross-platform document format and conversion of Web page-image backups to native PDF (and PDF rendering back into Web page images) are planned separately; do not assume a backup created on one client is currently restorable in the other client.


## PDF tools license (mobile app)

The advanced PDF tools use Syncfusion Flutter PDF for importing, combining, splitting, optimizing, and password-protecting existing PDFs. Syncfusion is commercially licensed; eligible individuals and small organizations may qualify for its Community License. Review the current eligibility and license terms at https://www.syncfusion.com/products/communitylicense before publishing. No runtime license key registration is required for modern Syncfusion Flutter packages, but you must still meet the Community License eligibility rules or obtain a commercial license before distribution.

The handwritten signature feature places a visible signature image on the first page. It is not a certificate-backed cryptographic digital signature. PDF compression currently applies document-level optimization; it may not substantially reduce PDFs whose size is dominated by embedded images.
