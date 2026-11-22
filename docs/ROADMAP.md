# Production roadmap

The repository provides a useful cross-platform starting point, not a finished CamScanner clone. Recommended implementation sequence:

1. **Native document detection:** implemented for Android/iOS using the native scanner flow (ML Kit on Android and VisionKit on iOS) with automatic edge detection, auto-capture, perspective correction and multi-page capture. The web PWA keeps browser camera/gallery capture and manual crop.
2. **Native image pipeline:** native scanner enhancement is available; add a dedicated non-destructive pipeline for deskew, adaptive threshold, shadow removal and custom filter presets.
3. **Native OCR:** English on-device OCR is implemented for Android/iOS using ML Kit; persist extracted text and add searchable page-level results. Web OCR is currently browser-based.
4. **Persistent Flutter library:** copy imported/captured images into app documents storage, add SQLite/Drift metadata, folders, rename, reorder, tags and deletion.
5. **PDF suite:** merge/split/reorder/compress, password-protected export, page size/orientation, margins, watermark, signature and print.
6. **Cloud sync:** Firebase Auth + private Storage + Firestore metadata, per-user security rules, resumable uploads, offline queue, conflict resolution, account deletion and restore testing.
7. **Release engineering:** production upload keystore, Play App Signing, iOS signing, privacy policy, data-safety declarations, accessibility and device QA.

## Cloud implementation status

Firebase setup instructions and deployable Firestore/Storage rules are in `FIREBASE_SETUP.md` and `firebase/`. Cloud backup is opt-in and user-initiated. Cloud deletion propagation and conflict handling are not implemented.

## Cloud security baseline

Never use public read/write Firebase Storage rules. Scope each object under `users/{uid}/...`; require authenticated ownership in Storage and Firestore rules. Keep credentials and signing material in GitHub Actions Secrets, not in source control. Firebase client config is not a server secret, but security rules are mandatory.


## Delivered in this update
- Mobile PDF merge using page templates, PDF split into one-page files, document optimization, AES-256 password protection, and visible handwritten signature placement. Web/PWA PDF merge, split-to-ZIP, object-stream optimization, and visible first-page signature placement.
- Local document folders with create and move actions.
- Advanced PDF processing depends on Syncfusion Flutter PDF; licensing must be reviewed before release.

## Known limitations
- The visible signature is not a cryptographic certificate-backed signature.
- PDF compression cannot guarantee a smaller result for every input; image downsampling is a future enhancement.
- Folder organization is currently local to the mobile app; web/PWA folders and cross-device folder synchronization are not yet implemented. PDF password encryption is currently mobile-only.
- Flutter compilation and device testing still require GitHub Actions / a Flutter environment.
