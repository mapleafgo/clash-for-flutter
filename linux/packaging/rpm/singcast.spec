# 打包的是预编译产物，不做 debuginfo 提取
%global debug_package %{nil}

Name:           singcast
Version:        1.1.16
Release:        1%{?dist}
Summary:        A clash GUI client based on Flutter
License:        MIT
URL:            https://github.com/mapleafgo/singcast
Source0:        %{name}-%{version}.tar.gz
BuildArch:      x86_64
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root
# 依赖手工声明：捆绑的 Flutter/Go 产物自带私有库，自动扫描会引入无法满足的项
AutoReqProv:    no
Requires:       gtk3
# Fedora 系的二进制包名带 -gtk3 后缀，不存在裸 libayatana-appindicator 的 Provides
Requires:       libayatana-appindicator-gtk3
Requires:       polkit
Requires:       acl
Requires:       libcap

%description
A clash GUI client based on Flutter with sing-box core.

%prep
%setup -q
# Source tar 内含 bundle 全部文件 + singcast.desktop + singcast.svg + singcast-core

%install
install -d %{buildroot}/opt/Singcast
cp -a lib data %{buildroot}/opt/Singcast/
install -Dpm755 singcast %{buildroot}/opt/Singcast/singcast
install -Dpm755 singcast-core %{buildroot}/opt/Singcast/singcast-core
install -d %{buildroot}/usr/bin
ln -snf /opt/Singcast/singcast %{buildroot}/usr/bin/singcast
install -Dpm644 singcast.svg %{buildroot}/usr/share/icons/hicolor/scalable/apps/singcast.svg
install -Dpm644 singcast.desktop %{buildroot}/usr/share/applications/singcast.desktop
%post
# 与 deb/AUR/pkexec 同一行命令；只装配置，不重启运行中服务
/opt/Singcast/singcast-core service install 2>/dev/null || true

%preun
if [ "$1" = 0 ]; then
  /opt/Singcast/singcast-core service uninstall 2>/dev/null || true
fi

%clean
rm -rf %{buildroot}

%files
/opt/Singcast
/usr/bin/singcast
/usr/share/icons/hicolor/scalable/apps/singcast.svg
/usr/share/applications/singcast.desktop

%changelog
* Sun Jul 26 2026 mapleafgo <mapleafgo@gmail.com> - 1.1.16-1
- 修复 Android VPN 路由环路导致整机断网
- 内核升级到 v1.1.20；修复多项打包与 CI 缺陷

* Sun Jul 26 2026 mapleafgo <mapleafgo@gmail.com> - 1.1.15-1
- 预装 systemd 服务 + polkit，保障开 TUN 零密码
