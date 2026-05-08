#include <stdlib.h>
#include <string.h>

/**
 * C callback wrapper for Go→Dart event delivery.
 *
 * Go calls the wrapper synchronously with a C string it frees immediately
 * after the wrapper returns.  The wrapper strdup's the string so the Dart
 * listener (which processes the event asynchronously) receives a stable
 * pointer that it frees later via malloc/free.
 */

typedef void (*CoreCallback)(int eventType, const char* data);

static CoreCallback _dart_listener = NULL;

static void _callback_wrapper(int eventType, const char* data) {
    if (_dart_listener != NULL && data != NULL) {
        char* copy = strdup(data);
        if (copy != NULL) {
            _dart_listener(eventType, copy);
        }
    }
}

__attribute__((visibility("default")))
void CallbackWrapperSetListener(CoreCallback cb) {
    _dart_listener = cb;
}

__attribute__((visibility("default")))
void* CallbackWrapperGetFn(void) {
    return (void*)_callback_wrapper;
}
