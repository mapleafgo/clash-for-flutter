package main

import (
	"errors"
	"fmt"
	"net/http"
	"strings"

	flutter "github.com/go-flutter-desktop/go-flutter"
	"github.com/go-flutter-desktop/go-flutter/plugin"
	"github.com/go-gl/glfw/v3.3/glfw"
	"github.com/mapleafgo/sysproxy"
)

const channelName = "pac-proxy"
const port = "10081"
const defaultPac = `// Default PAC
var proxy = __PROXY__;
var direct = "DIRECT";

function FindProxyForURL(url, host) {
  if (isPlainHostName(host) ||
      shExpMatch(host, "*.local") ||
      isInNet(dnsResolve(host), "10.0.0.0", "255.0.0.0") ||
      isInNet(dnsResolve(host), "172.16.0.0",  "255.240.0.0") ||
      isInNet(dnsResolve(host), "192.168.0.0",  "255.255.0.0") ||
      isInNet(dnsResolve(host), "127.0.0.0", "255.255.255.0")) {
    return direct;
  }
  return proxy + direct;
}
`

type PACProxy struct {
	PacStr string
}

func init() {
	// Only the init function can be tweaked by plugin maker.
	options = append(options, flutter.AddPlugin(&PACProxy{}))
}

// InitPlugin initializes the plugin.
func (p *PACProxy) InitPlugin(messenger plugin.BinaryMessenger) error {
	channel := plugin.NewMethodChannel(messenger, channelName, plugin.StandardMethodCodec{})
	channel.HandleFunc("init", p.initPac)
	channel.HandleFunc("open", p.open)
	channel.HandleFunc("close", p.close)

	http.HandleFunc("/pac", func(resp http.ResponseWriter, req *http.Request) {
		fmt.Fprintf(resp, p.PacStr, req.URL.Query().Get("p"))
	})
	go http.ListenAndServe(fmt.Sprintf(":%s", port), nil)

	return nil
}

// InitPluginGLFW is called after the call to InitPlugin. When an error is
// returned it is printend the application is stopped.
func (p *PACProxy) InitPluginGLFW(window *glfw.Window) error {
	var previousCloseCallback glfw.CloseCallback
	previousCloseCallback = window.SetCloseCallback(func(w *glfw.Window) {
		if previousCloseCallback != nil {
			previousCloseCallback(w)
		}
		if w.ShouldClose() {
			_ = pacProxyClose()
		}
	})
	return nil
}

func (p *PACProxy) initPac(arguments interface{}) (reply interface{}, err error) {
	if arguments != nil && arguments != "" {
		pacStr := arguments.(string)
		p.PacStr = pacStr
		return nil, nil
	}
	p.PacStr = strings.ReplaceAll(defaultPac, "__PROXY__", `"SOCKS5 127.0.0.1:%s;"`)
	return nil, nil
}

func (p *PACProxy) open(arguments interface{}) (reply interface{}, err error) {
	if p.PacStr == "" {
		return nil, errors.New("pac初始化尚未完成")
	}
	cport := arguments.(string)
	return nil, sysproxy.TurnOnSystemProxy(fmt.Sprintf("http://127.0.0.1:%s/pac?p=%s", port, cport))
}

func (p *PACProxy) close(interface{}) (reply interface{}, err error) {
	return nil, sysproxy.TurnOffSystemProxy()
}

func pacProxyClose() error {
	return sysproxy.TurnOffSystemProxy()
}
