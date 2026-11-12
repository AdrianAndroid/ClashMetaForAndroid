#pragma once

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>

#define TAG "ClashCore"

typedef const char *c_string;

// Callback table registered by the host (Swift / ObjC).
// Every entry is optional: the dispatch functions below check for NULL first.

typedef void (*clash_log_func)(int level, const char *message);

typedef void (*clash_mark_socket_func)(void *tun_interface, int fd);

typedef int (*clash_query_socket_uid_func)(void *tun_interface, int protocol, const char *source, const char *target);

typedef void (*clash_complete_func)(void *completable, const char *exception);

typedef void (*clash_fetch_report_func)(void *fetch_callback, const char *status_json);

typedef void (*clash_fetch_complete_func)(void *fetch_callback, const char *error);

typedef int (*clash_logcat_received_func)(void *logcat_interface, const char *payload);

typedef int (*clash_open_content_func)(const char *url, char *error, int error_length);

typedef void (*clash_release_object_func)(void *obj);

typedef struct clash_callbacks {
    clash_log_func log;
    clash_mark_socket_func mark_socket;
    clash_query_socket_uid_func query_socket_uid;
    clash_complete_func complete;
    clash_fetch_report_func fetch_report;
    clash_fetch_complete_func fetch_complete;
    clash_logcat_received_func logcat_received;
    clash_open_content_func open_content;
    clash_release_object_func release_object;
} clash_callbacks;

// Implemented in bridge.c, called from the Go export coreRegisterCallbacks.
void core_register_callbacks(clash_callbacks *callbacks);

extern void (*mark_socket_func)(void *tun_interface, int fd);

extern int (*query_socket_uid_func)(void *tun_interface, int protocol, const char *source, const char *target);

extern void (*complete_func)(void *completable, const char *exception);

extern void (*fetch_report_func)(void *fetch_callback, const char *status_json);

extern void (*fetch_complete_func)(void *fetch_callback, const char *error);

extern int (*logcat_received_func)(void *logcat_interface, const char *payload);

extern void (*release_object_func)(void *obj);

extern int (*open_content_func)(const char *url, char *error, int error_length);

extern void (*native_log_func)(int level, const char *message);

// cgo entry points
extern void mark_socket(void *interface, int fd);

extern int query_socket_uid(void *interface, int protocol, char *source, char *target);

extern void complete(void *obj, char *error);

extern void fetch_complete(void *fetch_callback, char *exception);

extern void fetch_report(void *fetch_callback, char *status_json);

extern int logcat_received(void *logcat_interface, char *payload);

extern void release_object(void *obj);

extern int open_content(char *url, char *error, int error_length);

extern void log_info(char *msg);

extern void log_error(char *msg);

extern void log_warn(char *msg);

extern void log_debug(char *msg);

extern void log_verbose(char *msg);
