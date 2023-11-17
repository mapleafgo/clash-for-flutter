package main

import "C"
import (
	"github.com/Dreamacro/clash/config"
	"github.com/Dreamacro/clash/constant"
	"github.com/Dreamacro/clash/hub"
	"github.com/oschwald/geoip2-golang"
	"log"
	"os"
	"path/filepath"
)

var options []hub.Option

func init() {
	constant.Version = "v1.18.0"
}

//export setHomeDir
func setHomeDir(homeStr *C.char) bool {
	homeDir := C.GoString(homeStr)
	info, err := os.Stat(homeDir)
	if err != nil {
		log.Printf("clash_lib [setHomeDir]: %s : %+v\n", homeDir, err)
		return false
	}
	if !info.IsDir() {
		log.Printf("clash_lib [setHomeDir]: Path is not directory %s\n", homeDir)
		return false
	}
	constant.SetHomeDir(homeDir)
	return true
}

//export setConfig
func setConfig(configStr *C.char) bool {
	configFile := C.GoString(configStr)
	if configFile == "" {
		return false
	}
	if !filepath.IsAbs(configFile) {
		configFile = filepath.Join(constant.Path.HomeDir(), configFile)
	}
	constant.SetConfig(configFile)
	return true
}

//export withExternalController
func withExternalController(externalController *C.char) {
	options = append(options, hub.WithExternalController(C.GoString(externalController)))
}

//export withSecret
func withSecret(secret *C.char) {
	options = append(options, hub.WithSecret(C.GoString(secret)))
}

//export mmdbVerify
func mmdbVerify(path *C.char) bool {
	instance, err := geoip2.Open(C.GoString(path))
	if err == nil {
		_ = instance.Close()
	}
	return err == nil
}

//export startService
func startService() bool {
	if err := config.Init(constant.Path.HomeDir()); err != nil {
		log.Printf("clash_lib [startService]: Initial error: %+v\n", err)
		return false
	}
	err := hub.Parse(options...)
	if err != nil {
		log.Printf("clash_lib [startService]: %+v\n", err)
		return false
	}
	return true
}

func main() {
	log.Println("hello clash")
}
