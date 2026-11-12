//go:build darwin

package platform

import "net"

func QuerySocketUidFromProcFs(source, target net.Addr) int {
	return -1
}
