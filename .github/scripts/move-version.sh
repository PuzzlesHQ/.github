#!/bin/bash
set -e

# === CONFIG ===
MAVEN_URL="${MAVEN_URL:?MAVEN_URL not set}"
SOURCE_REPO="${SOURCE_REPO:-releases}"
DEST_REPO="${DEST_REPO:-archived}"
GROUP_ID="${GROUP_ID:-dev.puzzleshq}"
ARTIFACT_ID="${ARTIFACT_ID:-test}"
VERSION="${VERSION:-69.69.69}"
AUTH="${MAVEN_NAME:?MAVEN_NAME not set}:${MAVEN_SECRET:?MAVEN_SECRET not set}"

# === Path conversions ===
GROUP_PATH="${GROUP_ID//.//}" # convert dots to slashes
ARTIFACT_PATH="$GROUP_PATH/$ARTIFACT_ID/$VERSION"
SOURCE_URL="$MAVEN_URL/$SOURCE_REPO/$ARTIFACT_PATH"

# === Known Maven files ===
FILES=(
  "$ARTIFACT_ID-$VERSION.jar"
  "$ARTIFACT_ID-$VERSION.pom"
  "$ARTIFACT_ID-$VERSION.module"
  "$ARTIFACT_ID-$VERSION-javadoc.jar"
  "$ARTIFACT_ID-$VERSION-sources.jar"
)

# === Optional checksums ===
EXTS=("md5" "sha1" "sha256" "sha512")

# Add checksum files to the array
CHECKSUM_FILES=()
for file in "${FILES[@]}"; do
  CHECKSUM_FILES+=("$file")
  for ext in "${EXTS[@]}"; do
    CHECKSUM_FILES+=("$file.$ext")
  done
done

FOUND_FILES=()

# === Step 1: Download files ===
echo "Downloading files from $SOURCE_URL"
for file in "${CHECKSUM_FILES[@]}"; do
  if curl --fail --silent --output "$file" -u "$AUTH" "$SOURCE_URL/$file"; then
    FOUND_FILES+=("$file")
    echo "Downloaded: $file"
  else
    echo "Skipped (not found): $file"
  fi
done

# Check if any files were found and downloaded
if [ ${#FOUND_FILES[@]} -eq 0 ]; then
  echo "No files were downloaded — aborting."
  exit 1
fi

# === Step 2: Create temporary working directory ===
TMP_DIR=$(mktemp -d)
cd "$TMP_DIR" || exit 1  # Ensure we can enter the directory

# Downloading all files again into the temporary directory
for file in "${FOUND_FILES[@]}"; do
  echo "→ Downloading $file"
  curl -sSf -u "$AUTH" -O "$SOURCE_URL/$file" || echo "Skipped: $file"
done

# === Step 3: Upload files to archived repository ===
echo "Uploading to $DEST_REPO"
ls -l "$TMP_DIR"
for file in $TMP_DIR; do
  echo "→ Uploading $file"
  curl -sSf -X PUT -u "$AUTH" \
    --data-binary @"$file" "$MAVEN_URL/api/repository/$DEST_REPO/$ARTIFACT_PATH/$file" || {
    echo "Failed to upload $file"
    exit 1
  }
done

# === Step 4: Delete original version ===
echo "Deleting from $SOURCE_REPO"
curl -sSf -X DELETE -u "$AUTH" \
  "$MAVEN_URL/api/repository/$SOURCE_REPO/$ARTIFACT_PATH" || {
    echo "Failed to delete from $SOURCE_REPO"
    exit 1
}

# === Done ===
echo "Successfully moved $ARTIFACT_ID:$VERSION from '$SOURCE_REPO' to '$DEST_REPO'"

# === Cleanup ===
cd - > /dev/null
rm -rf "$TMP_DIR" || exit 1
