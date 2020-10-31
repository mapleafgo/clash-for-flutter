package main

import (
	"bytes"
	"errors"
	"fmt"
	"net/http"
	"strings"

	"github.com/fanlide/sysproxy/cmd"
	"github.com/gin-gonic/gin"
	flutter "github.com/go-flutter-desktop/go-flutter"
	"github.com/go-flutter-desktop/go-flutter/plugin"
	"github.com/go-gl/glfw/v3.3/glfw"
)

const channelName = "pac-proxy"
const port = "10080"

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

	router := gin.New()
	router.GET("/pac", func(c *gin.Context) {
		c.String(http.StatusOK, p.PacStr, c.Query("p"))
	})
	go router.Run(fmt.Sprintf(":%s", port))

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
			pacProxyClose()
		}
	})
	return nil
}

func (p *PACProxy) initPac(arguments interface{}) (reply interface{}, err error) {
	if params, ok := arguments.([]interface{}); ok {
		if params[0] != nil && params[0] != "" {
			pacStr := params[0].(string)
			p.PacStr = pacStr
			return nil, nil
		}
	}
	resp, err := http.Get("https://hub.fastgit.org/iBug/pac/releases/latest/download/pac-gfwlist-17mon.txt")
	if err != nil {
		return nil, err
	}
	buf := new(bytes.Buffer)
	buf.ReadFrom(resp.Body)
	p.PacStr = strings.ReplaceAll(buf.String(), "__PROXY__", "\"SOCKS5 127.0.0.1:%s;\"")
	return nil, nil
}

func (p *PACProxy) open(arguments interface{}) (reply interface{}, err error) {
	if p.PacStr == "" {
		return nil, errors.New("pac文件尚未初始化")
	}
	if params, ok := arguments.([]interface{}); ok {
		if params[0] != nil {
			cport := params[0].(string)
			return nil, cmd.TurnOnSystemProxy(fmt.Sprintf("http://127.0.0.1:%s/pac?p=%s", port, cport))
		}
	}
	return nil, errors.New("参数错误")
}

func (p *PACProxy) close(arguments interface{}) (reply interface{}, err error) {
	return nil, cmd.TurnOffSystemProxy()
}

func pacProxyClose() error {
	return cmd.TurnOffSystemProxy()
}
