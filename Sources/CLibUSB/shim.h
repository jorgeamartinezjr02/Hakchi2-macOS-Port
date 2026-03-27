#ifndef CLIBUSB_SHIM_H
#define CLIBUSB_SHIM_H

#if __has_include(<libusb-1.0/libusb.h>)
#include <libusb-1.0/libusb.h>
#elif __has_include("/opt/homebrew/include/libusb-1.0/libusb.h")
#include "/opt/homebrew/include/libusb-1.0/libusb.h"
#elif __has_include("/usr/local/include/libusb-1.0/libusb.h")
#include "/usr/local/include/libusb-1.0/libusb.h"
#else
#error "libusb not found. Install with: brew install libusb"
#endif

#endif /* CLIBUSB_SHIM_H */
