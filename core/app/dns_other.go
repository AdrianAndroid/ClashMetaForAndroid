//go:build !(android && cmfa)

package app

import (
	"github.com/metacubex/mihomo/component/resolver"
)

// On Apple platforms the system DNS servers are configured through
// NEDNSSettings, so there is nothing to inject into the kernel. We only need to
// drop the cached state, mirroring the Android behaviour.
func updateSystemDNS(_ []string) {}

func flushDNS() {
	resolver.ClearCache()
	resolver.ResetConnection()
}
