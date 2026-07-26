Name:           singcast
Version:        1.1.15
Release:        1%{?dist}
Summary:        A clash GUI client based on Flutter
License:        MIT
URL:            https://github.com/mapleafgo/singcast
Source0:        %{name}-%{version}.tar.gz
BuildArch:      x86_64
BuildRoot:      %{_tmppath}/%{name}-%{version}-%{release}-root
Requires:       gtk3
Requires:       libayatana-appindicator
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
* Sun Jul 26 2026 mapleafgo <mapleafgo@gmail.com> - 1.1.15-1
- 预装 systemd 服务 + polkit，保障开 TUN 零密码
