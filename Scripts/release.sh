#!/usr/bin/env bash
#
# release.sh — cut a Keystone release the built-in auto-updater can consume.
#
# Steps:
#   1. Preconditions (before any build): clean git tree, local tag vX == HEAD,
#      the same tag exists on origin at the same commit.
#   2. Build the versioned .app, then check its Info.plist version + bundle id.
#   3. Codesign with Hardened Runtime + entitlements, verify, assert the
#      runtime flag is set.
#   4. Zip, then sign the zip with the Ed25519 update key.
#   5. Verify that signature against the public key EMBEDDED in
#      App/Updater.swift (Scripts/verify_update.swift). Wrong private key =
#      every installed copy would reject the update, so abort here.
#   6. Create the GitHub Release (--verify-tag) with Keystone.zip +
#      Keystone.zip.sig.
# The app verifies that Ed25519 signature (embedded public key) before
# installing any update — see App/Updater.swift.
#
# Usage:
#   Scripts/release.sh <version>            # e.g. Scripts/release.sh 1.0.1
#
# Env (optional):
#   KEYSTONE_SIGN_IDENTITY   codesign identity. Default "-" (ad-hoc). Set to a
#                            stable self-signed identity name (e.g.
#                            "Keystone Self-Signed") so Accessibility grants
#                            persist across auto-updates.
#   KEYSTONE_ED25519_KEY     path to the base64 Ed25519 private key.
#                            Default: ~/.config/keystone/ed25519_private.b64
#   KEYSTONE_REPO            GitHub repo. Default: tanhattan0051/Keystone
#   KEYSTONE_RELEASE_DRY_RUN=1
#                            Run every step except `gh release create` (it is
#                            only printed). The clean-tree and tag checks
#                            (local + remote) become warnings so the
#                            build/sign/verify path can run on an untagged tree.

set -euo pipefail

VERSION="${1:-}"
if [[ -z "${VERSION}" ]]; then
    echo "usage: Scripts/release.sh <version>   (e.g. 1.0.1)" >&2
    exit 2
fi
if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: version must be MAJOR.MINOR.PATCH (got '${VERSION}')" >&2
    exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST="${REPO_ROOT}/dist"
APP="${DIST}/Keystone.app"
ZIP="${DIST}/Keystone.zip"
SIG="${DIST}/Keystone.zip.sig"

SIGN_IDENTITY="${KEYSTONE_SIGN_IDENTITY:--}"
PRIV_KEY="${KEYSTONE_ED25519_KEY:-${HOME}/.config/keystone/ed25519_private.b64}"
REPO="${KEYSTONE_REPO:-tanhattan0051/Keystone}"

DRY_RUN="${KEYSTONE_RELEASE_DRY_RUN:-0}"
TAG="v${VERSION}"
EXPECTED_BUNDLE_ID="com.tanta.keystone"
INFO_PLIST="${APP}/Contents/Info.plist"
UPDATER_SWIFT="${REPO_ROOT}/App/Updater.swift"

# A failed precondition is an error, except in dry-run where it is only a
# warning (so the build/sign/verify path is testable on an untagged tree).
precondition_failed() {
    if [[ "${DRY_RUN}" == "1" ]]; then
        echo "warning (dry-run, continuing): $1" >&2
    else
        echo "error: $1" >&2
        exit 1
    fi
}

for tool in swift ditto codesign gh git /usr/libexec/PlistBuddy; do
    command -v "${tool}" >/dev/null 2>&1 || { echo "error: '${tool}' not found in PATH" >&2; exit 1; }
done
[[ -f "${PRIV_KEY}" ]] || { echo "error: Ed25519 private key not found at ${PRIV_KEY}" >&2; exit 1; }

echo "==> Checking git preconditions"
if [[ -n "$(git -C "${REPO_ROOT}" status --porcelain)" ]]; then
    precondition_failed "working tree is not clean. Commit or discard changes first (dist/ and .build/ are gitignored)."
fi

HEAD_COMMIT="$(git -C "${REPO_ROOT}" rev-parse HEAD)"
LOCAL_TAG_COMMIT="$(git -C "${REPO_ROOT}" rev-parse -q --verify "refs/tags/${TAG}^{commit}" || true)"
if [[ -z "${LOCAL_TAG_COMMIT}" ]]; then
    precondition_failed "local tag ${TAG} does not exist. Create and push it: git tag ${TAG} && git push origin ${TAG}"
elif [[ "${LOCAL_TAG_COMMIT}" != "${HEAD_COMMIT}" ]]; then
    precondition_failed "tag ${TAG} points at ${LOCAL_TAG_COMMIT}, but HEAD is ${HEAD_COMMIT}. Check out the tagged commit, or move the tag if it was never pushed."
fi

# ls-remote lists a lightweight tag as one line (the commit) and an annotated
# tag as two: the tag object plus a peeled "^{}" line holding the commit.
# Prefer the peeled line when present.
REMOTE_TAGS=""
if ! REMOTE_TAGS="$(git -C "${REPO_ROOT}" ls-remote --tags origin "refs/tags/${TAG}" "refs/tags/${TAG}^{}")"; then
    precondition_failed "cannot query remote 'origin' for tags (network/auth problem?)."
fi
REMOTE_TAG_COMMIT="$(awk -v ref="refs/tags/${TAG}" '
    $2 == ref"^{}" { peeled = $1 }
    $2 == ref      { direct = $1 }
    END { print (peeled != "" ? peeled : direct) }' <<< "${REMOTE_TAGS}")"
if [[ -z "${REMOTE_TAG_COMMIT}" ]]; then
    precondition_failed "tag ${TAG} is not on origin. Push it: git push origin ${TAG}"
elif [[ "${REMOTE_TAG_COMMIT}" != "${HEAD_COMMIT}" ]]; then
    precondition_failed "origin's ${TAG} points at ${REMOTE_TAG_COMMIT}, but HEAD is ${HEAD_COMMIT}. The remote tag must match what is being built."
fi

echo "==> Building Keystone.app v${VERSION}"
KEYSTONE_VERSION="${VERSION}" bash "${SCRIPT_DIR}/build_app.sh" "${DIST}"

echo "==> Checking built bundle metadata"
BUILT_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
if [[ "${BUILT_VERSION}" != "${VERSION}" ]]; then
    echo "error: built app reports version '${BUILT_VERSION}', expected '${VERSION}'" >&2
    exit 1
fi
if [[ "${BUILT_BUNDLE_ID}" != "${EXPECTED_BUNDLE_ID}" ]]; then
    echo "error: built app bundle id is '${BUILT_BUNDLE_ID}', expected '${EXPECTED_BUNDLE_ID}'" >&2
    exit 1
fi

# Hardened Runtime is fine even with an ad-hoc identity: Keystone links only
# Apple system frameworks, so library validation is satisfied. The entitlements
# file is empty on purpose (no exceptions needed). CGEventTap / Accessibility
# need TCC grants from the user, not entitlements.
echo "==> Codesigning (${SIGN_IDENTITY}) with Hardened Runtime"
codesign --force --deep --options runtime \
    --entitlements "${REPO_ROOT}/App/Keystone.entitlements" \
    --sign "${SIGN_IDENTITY}" "${APP}"
codesign --verify --deep --strict --verbose=2 "${APP}"
CODESIGN_INFO="$(codesign -dv "${APP}" 2>&1)"
if ! grep -E 'flags=.*runtime' <<< "${CODESIGN_INFO}" >/dev/null; then
    echo "error: codesign did not apply the Hardened Runtime flag. codesign -dv said:" >&2
    echo "${CODESIGN_INFO}" >&2
    exit 1
fi

echo "==> Zipping -> ${ZIP}"
rm -f "${ZIP}" "${SIG}"
ditto -c -k --sequesterRsrc --keepParent "${APP}" "${ZIP}"

echo "==> Signing the zip with the Ed25519 update key"
swift "${SCRIPT_DIR}/sign_update.swift" "${PRIV_KEY}" "${ZIP}" > "${SIG}"
echo "    signature: $(cat "${SIG}")"

echo "==> Verifying the signature against the key embedded in App/Updater.swift"
EMBEDDED_KEY="$(sed -n 's/.*embeddedPublicKeyBase64 = "\([^"]*\)".*/\1/p' "${UPDATER_SWIFT}")"
if [[ -z "${EMBEDDED_KEY}" || "$(wc -l <<< "${EMBEDDED_KEY}" | tr -d ' ')" != "1" ]]; then
    echo "error: expected exactly one non-empty embeddedPublicKeyBase64 in ${UPDATER_SWIFT}, got: '${EMBEDDED_KEY}'" >&2
    exit 1
fi
if ! swift "${SCRIPT_DIR}/verify_update.swift" "${EMBEDDED_KEY}" "${ZIP}" "${SIG}"; then
    echo "error: the zip signature does not verify against the embedded public key." >&2
    echo "       KEYSTONE_ED25519_KEY (${PRIV_KEY}) is probably not the matching private key." >&2
    echo "       Publishing would make every installed copy reject the update. Aborting." >&2
    exit 1
fi

echo "==> Creating GitHub Release v${VERSION} on ${REPO}"
NOTES="$(cat <<NOTE
Keystone v${VERSION}

Cài đặt lần đầu: tải Keystone.zip, giải nén, kéo Keystone.app vào /Applications.
Vì app chưa notarize (không có tài khoản Apple Developer), lần đầu macOS sẽ cảnh
báo — **chuột phải vào Keystone.app → Mở** (chỉ cần một lần). Từ các bản sau, app
tự cập nhật (đã xác thực bằng chữ ký Ed25519).
NOTE
)"

# --verify-tag: refuse to let gh create the tag itself (it would tag the remote
# default branch, which may differ from what was just built).
RELEASE_CMD=(gh release create "${TAG}" "${ZIP}" "${SIG}"
    --repo "${REPO}"
    --verify-tag
    --title "Keystone v${VERSION}"
    --notes "${NOTES}")

if [[ "${DRY_RUN}" == "1" ]]; then
    echo "    (dry-run) would run:"
    printf '      %q' "${RELEASE_CMD[@]}"; echo
    echo "==> Dry run finished. Nothing was published."
    exit 0
fi

"${RELEASE_CMD[@]}"

echo "==> Done. Release v${VERSION} published with Keystone.zip + Keystone.zip.sig."
