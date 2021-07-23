module github.com/mapleafgo/clash-for-flutter/go

go 1.16

require (
	github.com/go-flutter-desktop/go-flutter v0.43.0
	github.com/go-flutter-desktop/plugins/path_provider v0.4.0
	github.com/go-gl/glfw/v3.3/glfw v0.0.0-20210410170116-ea3d685f79fb
	github.com/mapleafgo/go-flutter-clash/go v0.0.0-20210622080346-be32a554e800
	github.com/mapleafgo/go-flutter-systray/go v0.0.0-20210413014355-59e3141b1836
	github.com/pkg/errors v0.9.1
	github.com/wzshiming/sysproxy v0.2.1
)

// replace github.com/mapleafgo/go-flutter-clash/go => ../../go-flutter-clash/go
// replace github.com/wzshiming/sysproxy => ../../sysproxy/
