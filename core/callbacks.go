package main

/*
#include "bridge.h"
*/
import "C"

//export coreRegisterCallbacks
func coreRegisterCallbacks(callbacks *C.clash_callbacks) {
	C.core_register_callbacks(callbacks)
}
