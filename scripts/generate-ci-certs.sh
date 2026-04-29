#!/bin/bash
# 生成 CI 签名证书脚本
# 用于在 GitHub Secrets 中配置一致的打包签名

set -e

CERTS_DIR="ci-certs"
mkdir -p "$CERTS_DIR"

echo "=== 生成 CI 签名证书 ==="

# 1. Android Keystore
echo ""
echo "1. 生成 Android Keystore..."
read -sp "请输入 keystore 密码: " STORE_PASSWORD
echo ""
read -sp "请输入 key 密码: " KEY_PASSWORD
echo ""
read -p "请输入 key 别名 [singcast]: " KEY_ALIAS
KEY_ALIAS=${KEY_ALIAS:-singcast}

keytool -genkey -v \
  -storetype JKS \
  -keystore "$CERTS_DIR/release.jks" \
  -keyalg RSA \
  -keysize 2048 \
  -validity 10000 \
  -alias "$KEY_ALIAS" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=Singcast, OU=Development, O=mapleafgo, L=Unknown, ST=Unknown, C=CN"

# 转为 base64
ANDROID_KEYSTORE_BASE64=$(base64 -i "$CERTS_DIR/release.jks" | tr -d '\n')

echo ""
echo "=== GitHub Secrets 配置 ==="
echo ""
echo "请在 GitHub 仓库 Settings -> Secrets and variables -> actions 中添加以下 Secrets："
echo ""
echo "ANDROID_KEYSTORE_BASE64:"
echo "$ANDROID_KEYSTORE_BASE64"
echo ""
echo "ANDROID_KEYSTORE_PASSWORD: $STORE_PASSWORD"
echo "ANDROID_KEY_PASSWORD: $KEY_PASSWORD"
echo "ANDROID_KEY_ALIAS: $KEY_ALIAS"
echo ""
echo "=== 安全提示 ==="
echo "1. 复制上述 Secrets 到 GitHub 仓库配置"
echo "2. 删除本地证书文件: rm -rf $CERTS_DIR"
echo "3. 证书文件不应提交到仓库（已添加到 .gitignore）"
echo ""
echo "=== macOS ==="
echo "macOS 使用 ad-hoc 签名 (--)，无需配置证书。"
echo "如需正式签名，需要 Apple Developer 账号并配置以下 Secrets："
echo "  - MACOS_CERTIFICATE_BASE64: P12 证书 base64"
echo "  - MACOS_CERTIFICATE_PASSWORD: P12 证书密码"
echo "  - MACOS_SIGNING_IDENTITY: 签名标识"
echo ""
echo "=== Windows ==="
echo "Windows 暂不配置代码签名，使用 Inno Setup 打包。"
echo "如需签名，需要代码签名证书并配置以下 Secrets："
echo "  - WINDOWS_CERTIFICATE_BASE64: PFX 证书 base64"
echo "  - WINDOWS_CERTIFICATE_PASSWORD: PFX 证书密码"
echo ""
echo "证书已保存到 $CERTS_DIR/ 目录"
