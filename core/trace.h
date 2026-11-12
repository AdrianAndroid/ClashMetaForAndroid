#pragma once

#include <stdio.h>

#define ENABLE_TRACE 0

#if ENABLE_TRACE

extern void trace_method_exit(const char **name);

#define TRACE_METHOD() __attribute__((cleanup(trace_method_exit))) const char *__method_name = __FUNCTION__; fprintf(stderr, "TRACE-IN  %s\n", __method_name)

#else

#define TRACE_METHOD()

#endif
