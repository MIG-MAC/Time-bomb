#!/bin/bash
set -e

# Couleurs pour l'affichage
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Chemins
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_ROOT="$(dirname "$SCRIPT_DIR")"
RUST_ROOT="$APP_ROOT/../../time_bomb_core"
LIB_DIR="$APP_ROOT/libtime_bomb"
JNILIBS_DIR="$APP_ROOT/android/app/src/main/jniLibs"

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  Time Bomb Native Libs Build Script${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Vérifier que le dossier Rust existe
if [ ! -d "$RUST_ROOT" ]; then
    echo -e "${YELLOW}⚠️  Rust core not found at: $RUST_ROOT${NC}"
    exit 1
fi

cd "$RUST_ROOT"
echo -e "${GREEN}📦 Building Rust core from: $RUST_ROOT${NC}"
echo ""

# ======================
# 1. Build iOS libraries
# ======================
echo -e "${BLUE}[1/3] Building iOS libraries...${NC}"

# Device (ARM64)
echo "  → Building for iOS device (arm64)..."
cargo build --release --target aarch64-apple-ios
cp target/aarch64-apple-ios/release/libtime_bomb_core.a \
   "$LIB_DIR/ios/libtime_bomb_core_ios_arm64.a"
echo -e "${GREEN}    ✓ libtime_bomb_core_ios_arm64.a${NC}"

# Simulator (ARM64 for Apple Silicon)
echo "  → Building for iOS simulator (arm64)..."
cargo build --release --target aarch64-apple-ios-sim
cp target/aarch64-apple-ios-sim/release/libtime_bomb_core.a \
   "$LIB_DIR/ios/libtime_bomb_core_ios_sim_arm64.a"
echo -e "${GREEN}    ✓ libtime_bomb_core_ios_sim_arm64.a${NC}"

# Simulator (x86_64 for Intel Macs)
echo "  → Building for iOS simulator (x86_64)..."
cargo build --release --target x86_64-apple-ios
cp target/x86_64-apple-ios/release/libtime_bomb_core.a \
   "$LIB_DIR/ios/libtime_bomb_core_ios_sim_x86_64.a"
echo -e "${GREEN}    ✓ libtime_bomb_core_ios_sim_x86_64.a${NC}"

# Create universal simulator library
echo "  → Creating universal simulator library..."
lipo -create \
    "$LIB_DIR/ios/libtime_bomb_core_ios_sim_arm64.a" \
    "$LIB_DIR/ios/libtime_bomb_core_ios_sim_x86_64.a" \
    -output "$LIB_DIR/ios/libtime_bomb_core_ios_sim_universal.a"
echo -e "${GREEN}    ✓ libtime_bomb_core_ios_sim_universal.a${NC}"

echo ""

# =========================
# 2. Build Android libraries
# =========================
echo -e "${BLUE}[2/3] Building Android libraries...${NC}"

cargo ndk \
    -t armeabi-v7a \
    -t arm64-v8a \
    -t x86_64 \
    -o "$LIB_DIR/android" \
    build --release

echo -e "${GREEN}    ✓ arm64-v8a/libtime_bomb_core.so${NC}"
echo -e "${GREEN}    ✓ armeabi-v7a/libtime_bomb_core.so${NC}"
echo -e "${GREEN}    ✓ x86_64/libtime_bomb_core.so${NC}"

echo ""

# ===============================
# 3. Sync to Android jniLibs
# ===============================
echo -e "${BLUE}[3/3] Syncing to Android jniLibs...${NC}"

# Créer les répertoires si nécessaire
mkdir -p "$JNILIBS_DIR/arm64-v8a"
mkdir -p "$JNILIBS_DIR/armeabi-v7a"
mkdir -p "$JNILIBS_DIR/x86_64"

# Copier les .so
cp "$LIB_DIR/android/arm64-v8a/libtime_bomb_core.so" \
   "$JNILIBS_DIR/arm64-v8a/"
echo -e "${GREEN}    ✓ Copied arm64-v8a${NC}"

cp "$LIB_DIR/android/armeabi-v7a/libtime_bomb_core.so" \
   "$JNILIBS_DIR/armeabi-v7a/"
echo -e "${GREEN}    ✓ Copied armeabi-v7a${NC}"

cp "$LIB_DIR/android/x86_64/libtime_bomb_core.so" \
   "$JNILIBS_DIR/x86_64/"
echo -e "${GREEN}    ✓ Copied x86_64${NC}"

echo ""
echo -e "${GREEN}========================================${NC}"
echo -e "${GREEN}✨ Build complete!${NC}"
echo -e "${GREEN}========================================${NC}"
echo ""
echo "Next steps:"
echo "  iOS:     cd ios && pod install && cd .. && flutter build ios"
echo "  Android: flutter build apk --debug"
echo ""
