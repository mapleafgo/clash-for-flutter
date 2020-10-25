module github.com/fanlide/clash_for_flutter/go

go 1.15

require (
	github.com/Xuanwo/go-locale v1.0.0 // indirect
	github.com/fanlide/go-flutter-clash/go v0.0.0-20201024084432-e4598f092534
	github.com/fanlide/sysproxy v0.0.0-20201024132447-a0915cc12b51
	github.com/gin-gonic/gin v1.6.3
	github.com/go-flutter-desktop/go-flutter v0.42.0
	github.com/pkg/errors v0.9.1
)

replace github.com/fanlide/go-flutter-clash/go => ..\..\go_flutter_clash\go
