# Release Checklist

Use this checklist before tagging a GitHub dev release.

## Before Tagging

1. Start from a clean worktree on `main`.
2. Run local verification:

   ```sh
   Scripts/verify-local.sh
   ```

3. Confirm the app version in `Resources/App/Info.plist` matches the intended tag.
4. Confirm no personal S3 endpoint, bucket, access key, secret key, or ZeroFS password appears in tracked files:

   ```sh
   rg -n "AKIA[0-9A-Z]{16}|AWS_SECRET_ACCESS_KEY|S3_SECRET_KEY|ZEROFS_PASSWORD|user-[0-9]{6,}" .
   ```

5. Push `main` and wait for CI to pass.

## Tag And Publish

Create and push the tag:

```sh
git tag v0.1.4
git push origin v0.1.4
```

The GitHub release workflow must upload:

- `ZeroFS-Manager-dev-adhoc.dmg`
- `ZeroFS-Manager-dev-adhoc.zip`
- `SHA256SUMS`

## Release Smoke Test

After the GitHub Release is published:

1. Download the DMG from the Release page.
2. Verify the checksum against `SHA256SUMS`.
3. Attach the DMG with `hdiutil attach`.
4. Copy `ZeroFS Manager.app` into `/Applications`.
5. Remove quarantine only for this ad-hoc GitHub build if Gatekeeper blocks testing:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/ZeroFS Manager.app"
   ```

6. Launch from `/Applications`, not from the mounted DMG.
7. Confirm ZeroFS CLI detection.
8. Configure a test profile, then run `Apply & Restart LaunchDaemon`.
9. After the sudo Terminal workflow finishes, verify the mount path and run `Test Now`.
10. If background probes are enabled, confirm a sanitized JSON result appears under `/Library/Application Support/ZeroFSManager/ProbeResults/<profile-id>/`.
11. Remove the test LaunchDaemon from the app or with the bundled uninstall workflow.

## Rollback

If the release workflow fails, delete the failed GitHub Release and tag, fix `main`, then create a new tag. Do not overwrite a published DMG with different contents under the same tag.
