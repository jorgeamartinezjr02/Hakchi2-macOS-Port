#ifndef CLIBSSH2_SHIM_H
#define CLIBSSH2_SHIM_H

#if __has_include(<libssh2.h>)
#include <libssh2.h>
#include <libssh2_sftp.h>
#elif __has_include("/opt/homebrew/include/libssh2.h")
#include "/opt/homebrew/include/libssh2.h"
#include "/opt/homebrew/include/libssh2_sftp.h"
#elif __has_include("/usr/local/include/libssh2.h")
#include "/usr/local/include/libssh2.h"
#include "/usr/local/include/libssh2_sftp.h"
#else
#error "libssh2 not found. Install with: brew install libssh2"
#endif

#endif /* CLIBSSH2_SHIM_H */
