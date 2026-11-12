#include "bridge.h"
#include "trace.h"

#include <stdio.h>

void (*mark_socket_func)(void *tun_interface, int fd);

int (*query_socket_uid_func)(void *tun_interface, int protocol, const char *source, const char *target);

void (*complete_func)(void *completable, const char *exception);

void (*fetch_report_func)(void *fetch_callback, const char *status_json);

void (*fetch_complete_func)(void *fetch_callback, const char *error);

int (*logcat_received_func)(void *logcat_interface, const char *payload);

int (*open_content_func)(const char *url, char *error, int error_length);

void (*release_object_func)(void *obj);

void (*native_log_func)(int level, const char *message);

void core_register_callbacks(clash_callbacks *callbacks) {
    if (callbacks == NULL) {
        return;
    }

    native_log_func = callbacks->log;
    mark_socket_func = callbacks->mark_socket;
    query_socket_uid_func = callbacks->query_socket_uid;
    complete_func = callbacks->complete;
    fetch_report_func = callbacks->fetch_report;
    fetch_complete_func = callbacks->fetch_complete;
    logcat_received_func = callbacks->logcat_received;
    open_content_func = callbacks->open_content;
    release_object_func = callbacks->release_object;
}

void mark_socket(void *interface, int fd) {
    TRACE_METHOD();

    if (mark_socket_func != NULL) {
        mark_socket_func(interface, fd);
    }
}

int query_socket_uid(void *interface, int protocol, char *source, char *target) {
    TRACE_METHOD();

    int result = -1;

    if (query_socket_uid_func != NULL) {
        result = query_socket_uid_func(interface, protocol, source, target);
    }

    free(source);
    free(target);

    return result;
}

void complete(void *obj, char *error) {
    TRACE_METHOD();

    if (complete_func != NULL) {
        complete_func(obj, error);
    }

    free(error);
}

void fetch_complete(void *fetch_callback, char *exception) {
    TRACE_METHOD();

    if (fetch_complete_func != NULL) {
        fetch_complete_func(fetch_callback, exception);
    }

    free(exception);
}

void fetch_report(void *fetch_callback, char *json_status) {
    TRACE_METHOD();

    if (fetch_report_func != NULL) {
        fetch_report_func(fetch_callback, json_status);
    }

    free(json_status);
}

int logcat_received(void *logcat_interface, char *payload) {
    TRACE_METHOD();

    int result = 0;

    if (logcat_received_func != NULL) {
        result = logcat_received_func(logcat_interface, payload);
    }

    free(payload);

    return result;
}

int open_content(char *url, char *error, int error_length) {
    TRACE_METHOD();

    int result = -1;

    if (open_content_func != NULL) {
        result = open_content_func(url, error, error_length);
    }

    free(url);

    return result;
}

void release_object(void *obj) {
    TRACE_METHOD();

    if (release_object_func != NULL) {
        release_object_func(obj);
    }
}

static void dispatch_log(int level, char *msg) {
    if (native_log_func != NULL) {
        native_log_func(level, msg);
    } else {
        fprintf(stderr, "[%s] %s\n", TAG, msg);
    }
}

void log_info(char *msg) {
    dispatch_log(0, msg);

    free(msg);
}

void log_error(char *msg) {
    dispatch_log(1, msg);

    free(msg);
}

void log_warn(char *msg) {
    dispatch_log(2, msg);

    free(msg);
}

void log_debug(char *msg) {
    dispatch_log(3, msg);

    free(msg);
}

void log_verbose(char *msg) {
    dispatch_log(4, msg);

    free(msg);
}
