package all

import (
	_ "cfa/app"
	_ "cfa/common"
	_ "cfa/config"
	_ "cfa/delegate"
	_ "cfa/platform"
	_ "cfa/proxy"
	_ "cfa/tun"
	_ "cfa/tunnel"

	_ "golang.org/x/sync/semaphore"

	_ "github.com/metacubex/mihomo/log"
)
