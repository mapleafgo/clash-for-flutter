#!/bin/bash
# Linux 打包脚本：flutter build → deb + rpm + zip + AppImage
# 用 dpkg-deb / rpmbuild / appimagetool / zip 手工打包。
set -euo pipefail

VERSION="${1:?usage: package-linux.sh <version> [output-dir]}"
OUTPUT_DIR="${2:-dist}"
APP_NAME="singcast"
DISPLAY_NAME="Singcast"
INSTALL_PATH="/opt/$DISPLAY_NAME"
BUNDLE="build/linux/x64/release/bundle"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [ ! -x "$BUNDLE/$APP_NAME" ]; then
  echo "Error: bundle not found at $BUNDLE. Run 'flutter build linux --release' first." >&2
  exit 1
fi

PKG_DIR="$OUTPUT_DIR/$VERSION"
mkdir -p "$PKG_DIR"

# ── DEB ──────────────────────────────────────────────────────────────
build_deb() {
  echo "Building deb..."
  local tmp; tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  # 文件布局
  mkdir -p "$tmp$INSTALL_PATH" "$tmp/usr/bin" "$tmp/usr/share/applications" "$tmp/usr/share/icons/hicolor/scalable/apps" "$tmp/DEBIAN"

  cp -a "$BUNDLE/." "$tmp$INSTALL_PATH/"
  ln -sf "$INSTALL_PATH/$APP_NAME" "$tmp/usr/bin/$APP_NAME"
  cp "$PROJECT_ROOT/linux/packaging/deb/DEBIAN/postinst" "$tmp/DEBIAN/postinst"
  cp "$PROJECT_ROOT/linux/packaging/deb/DEBIAN/prerm" "$tmp/DEBIAN/prerm"
  chmod 755 "$tmp/DEBIAN/postinst" "$tmp/DEBIAN/prerm"

  # desktop entry
  cat > "$tmp/usr/share/applications/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=$DISPLAY_NAME
Exec=$INSTALL_PATH/$APP_NAME %U
Terminal=false
Type=Application
Icon=$APP_NAME
StartupWMClass=$DISPLAY_NAME
Comment=A clash GUI client based on Flutter
Categories=Network;
MimeType=x-scheme-handler/clash;
EOF

  # icon (使用项目 assets)
  if [ -f "$PROJECT_ROOT/assets/icon.svg" ]; then
    cp "$PROJECT_ROOT/assets/icon.svg" "$tmp/usr/share/icons/hicolor/scalable/apps/$APP_NAME.svg"
  elif [ -f "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" ]; then
    cp "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" "$tmp/usr/share/icons/hicolor/scalable/apps/$APP_NAME.svg"
  fi

  # DEBIAN/control
  local size_kb; size_kb="$(du -sk "$tmp" | cut -f1)"
  cat > "$tmp/DEBIAN/control" <<EOF
Package: $APP_NAME
Version: $VERSION
Architecture: amd64
Maintainer: mapleafgo <mapleafgo@gmail.com>
Installed-Size: $size_kb
Depends: libgtk-3-0, libblkid1, liblzma5, libayatana-appindicator3-1, libnotify4, policykit-1, acl, libcap2-bin
Section: net
Priority: optional
Description: A clash GUI client based on Flutter
 A multi-platform Clash client powered by sing-box.
EOF

  dpkg-deb --build --root-owner-group "$tmp" "$PKG_DIR/$APP_NAME-$VERSION-linux.deb"
  echo "  → $PKG_DIR/$APP_NAME-$VERSION-linux.deb"
}

# ── ZIP (portable) ───────────────────────────────────────────────────
# ── RPM ──────────────────────────────────────────────────────────────
build_rpm() {
  echo "Building rpm..."
  if ! command -v rpmbuild >/dev/null 2>&1; then
    echo "  rpmbuild not found, skipping rpm" >&2
    return 0
  fi

  local spec="$PROJECT_ROOT/linux/packaging/rpm/singcast.spec"
  if [ ! -f "$spec" ]; then
    echo "  spec not found: $spec, skipping rpm" >&2
    return 0
  fi

  # 替换 spec 中的 Version 字段
  local tmp_spec; tmp_spec="$(mktemp)"
  sed "s/^Version:.*/Version:        $VERSION/" "$spec" > "$tmp_spec"

  local topdir; topdir="$(mktemp -d)"
  trap 'rm -rf "$topdir" "$tmp_spec"' RETURN
  mkdir -p "$topdir"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}

  # Source tar：把 bundle 打成 singcast-<version>/ 目录的 tar.gz
  local src_dir="$topdir/SOURCES/$APP_NAME-$VERSION"
  mkdir -p "$src_dir"
  cp -a "$BUNDLE/." "$src_dir/"

  # desktop entry + icon（spec install 需要它们在 Source 里）
  cat > "$src_dir/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=$DISPLAY_NAME
Exec=$INSTALL_PATH/$APP_NAME %U
Terminal=false
Type=Application
Icon=$APP_NAME
StartupWMClass=$DISPLAY_NAME
Comment=A clash GUI client based on Flutter
Categories=Network;
MimeType=x-scheme-handler/clash;
EOF
  if [ -f "$PROJECT_ROOT/assets/icon.svg" ]; then
    cp "$PROJECT_ROOT/assets/icon.svg" "$src_dir/$APP_NAME.svg"
  elif [ -f "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" ]; then
    cp "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" "$src_dir/$APP_NAME.svg"
  elif command -v convert >/dev/null 2>&1 && [ -f "$PROJECT_ROOT/assets/icon.png" ]; then
    # 从 PNG 生成 SVG 占位（rpm %files 需要）
    convert "$PROJECT_ROOT/assets/icon.png" "$src_dir/$APP_NAME.svg"
  else
    # 兜底：生成一个最小 SVG 占位图标
    cat > "$src_dir/$APP_NAME.svg" <<-'ICONEOF'
    <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
      <rect width="256" height="256" rx="48" fill="#6366f1"/>
      <path d="M80 192V64l96 64z" fill="#fff"/>
    </svg>
ICONEOF
  fi

  tar czf "$topdir/SOURCES/$APP_NAME-$VERSION.tar.gz" -C "$topdir/SOURCES" "$APP_NAME-$VERSION"

  # mktemp 生成的文件名是随机的，必须显式命名为 singcast.spec
  cp "$tmp_spec" "$topdir/SPECS/singcast.spec"
  rpmbuild -bb \
    --define "_topdir $topdir" \
    "$topdir/SPECS/singcast.spec" 2>&1 || {
      echo "  rpmbuild failed, skipping rpm" >&2
      return 0
    }

  find "$topdir/RPMS" -name '*.rpm' -exec cp {} "$PKG_DIR/" \;
  echo "  → rpm in $PKG_DIR/"
}

build_zip() {
  echo "Building zip..."
  local zip_path="$PKG_DIR/$APP_NAME-$VERSION-linux-amd64-portable.zip"
  (cd "$BUNDLE" && zip -r -y "$PROJECT_ROOT/$zip_path" .)
  echo "  → $zip_path"
}

# ── AppImage ─────────────────────────────────────────────────────────
build_appimage() {
  echo "Building AppImage..."
  if ! command -v appimagetool >/dev/null 2>&1; then
    echo "  appimagetool not found, skipping AppImage" >&2
    return 0
  fi

  local ai_dir; ai_dir="$(mktemp -d)"
  trap 'rm -rf "$ai_dir"' RETURN

  mkdir -p "$ai_dir/usr/bin" "$ai_dir/usr/lib" "$ai_dir/usr/share/applications" "$ai_dir/usr/share/icons/hicolor/scalable/apps"

  # AppDir 结构：所有文件放 usr/，AppRun 软链到主程序
  cp -a "$BUNDLE/." "$ai_dir/usr/"
  ln -sf "usr/$APP_NAME" "$ai_dir/AppRun"
  ln -sf "usr/$APP_NAME" "$ai_dir/$APP_NAME"

  cat > "$ai_dir/$APP_NAME.desktop" <<EOF
[Desktop Entry]
Name=$DISPLAY_NAME
Exec=$APP_NAME
Terminal=false
Type=Application
Icon=$APP_NAME
StartupWMClass=$DISPLAY_NAME
Comment=A clash GUI client based on Flutter
Categories=Network;
MimeType=x-scheme-handler/clash;
EOF
  cp "$ai_dir/$APP_NAME.desktop" "$ai_dir/usr/share/applications/$APP_NAME.desktop"

  # icon
  if [ -f "$PROJECT_ROOT/assets/icon.svg" ]; then
    cp "$PROJECT_ROOT/assets/icon.svg" "$ai_dir/$APP_NAME.svg"
  elif [ -f "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" ]; then
    cp "$PROJECT_ROOT/aurpkg/singcast/singcast.svg" "$ai_dir/$APP_NAME.svg"
  fi
  cp "$ai_dir/$APP_NAME.svg" "$ai_dir/usr/share/icons/hicolor/scalable/apps/$APP_NAME.svg" 2>/dev/null || true

  local output="$PKG_DIR/$APP_NAME-$VERSION-linux-amd64.AppImage"
  # CI runner 通常没有 FUSE，用 APPIMAGE_EXTRACT_AND_RUN 让 appimagetool 自解压运行
  ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 appimagetool "$ai_dir" "$output" 2>&1 || {
    echo "  appimagetool failed, skipping AppImage" >&2
    rm -f "$output"
    return 0
  }
  echo "  → $output"
}

build_deb
build_rpm
build_zip
build_appimage

echo "Done. Artifacts in $PKG_DIR/"
ls -lh "$PKG_DIR/"
