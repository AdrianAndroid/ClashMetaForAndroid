#include "trace.h"

#if ENABLE_TRACE

void trace_method_exit(const char **name) {
    fprintf(stderr, "TRACE-OUT %s\n", *name);
}

#endif
