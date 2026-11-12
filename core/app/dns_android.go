//go:build android && cmfa

package app

import (
	"github.com/metacubex/mihomo/dns"
)

func updateSystemDNS(addresses []string) {
	dns.UpdateSystemDNS(addresses)
}

func flushDNS() {
	dns.FlushCacheWithDefaultResolver()
}
