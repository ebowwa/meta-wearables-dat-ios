# Open Source Merge Strategy

This private repository (`meta-wearables-dat-ios-yolo`) contains proprietary YOLO integration features on top of the public open-source repository (`meta-wearables-dat-ios`).

## Repository Architecture

- **Public Repo**: `ebowwa/meta-wearables-dat-ios`
  - Contains the core DAT SDK.
  - Frameworks are located in `com.MWDAT/`.
  - Tracks upstream `facebook/meta-wearables-dat-ios`.

- **Private Repo**: `ebowwa/meta-wearables-dat-ios-yolo`
  - Contains everything in public repo + YOLO features.
  - Frameworks are located in `DAT/` (Legacy path).

## Merging Back Implementation

If you decide to open-source the YOLO features in the future, you can merge this history back into the public repository.

### Prerequisites

Ensure you have both remotes configured:

```bash
git remote add origin https://github.com/ebowwa/meta-wearables-dat-ios.git
git remote add private https://github.com/ebowwa/meta-wearables-dat-ios-yolo.git
```

### Merge Process

1. **Checkout the public main branch:**
   ```bash
   git checkout main
   git pull origin main
   ```

2. **Merge the private history:**
   Since both repositories share a common ancestor (commits from upstream Facebook), git can merge them. Use `--allow-unrelated-histories` if they have diverged significantly, but standard merge should work if history is preserved.

   ```bash
   git fetch private
   git merge private/main
   ```

3. **Resolve Conflicts:**
   You will likely encounter a tree conflict due to the folder rename:
   - Public: `com.MWDAT/`
   - Private: `DAT/`

   **Resolution Strategy:**
   - Keep `com.MWDAT/` as the canonical path.
   - Move any new files from `DAT/` (in private) into `com.MWDAT/`.
   - Update any internal references in the private code to point to `com.MWDAT`.

   ```bash
   # Example resolution if git doesn't auto-resolve the move
   git rm -r DAT
   # Move contents...
   ```

4. **Push to Public:**
   ```bash
   git push origin main
   ```
