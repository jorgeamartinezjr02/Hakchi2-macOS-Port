import Foundation
import Combine
import CLibUSB

final class USBDeviceMonitor: ObservableObject {
    @Published var deviceState: ConsoleState = .disconnected
    @Published var detectedConsoleType: ConsoleType = .unknown

    private var monitorTimer: Timer?
    private var isMonitoring = false
    /// Track whether we were previously connected so we can refresh the libusb
    /// context after a disconnect (macOS hot-plug workaround).
    private var wasConnected = false

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        monitorTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkForDevice()
        }
        monitorTimer?.tolerance = 0.5

        checkForDevice()
        HakchiLogger.usb.info("USB device monitoring started")
    }

    func stopMonitoring() {
        isMonitoring = false
        monitorTimer?.invalidate()
        monitorTimer = nil
        HakchiLogger.usb.info("USB device monitoring stopped")
    }

    private func checkForDevice() {
        // Create a fresh libusb context each poll to reliably detect
        // hot-plugged devices on macOS (persistent contexts can miss them).
        var ctx: OpaquePointer?
        guard libusb_init(&ctx) == 0 else {
            updateState(.disconnected, type: .unknown)
            return
        }
        defer { libusb_exit(ctx) }

        var deviceList: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(ctx, &deviceList)

        defer {
            if let list = deviceList {
                libusb_free_device_list(list, 1)
            }
        }

        guard count > 0, let list = deviceList else {
            if wasConnected {
                wasConnected = false
                updateState(.disconnected, type: .unknown)
                HakchiLogger.usb.info("Device disconnected")
            }
            return
        }

        var found = false
        for i in 0..<Int(count) {
            guard let device = list[i] else { continue }

            var descriptor = libusb_device_descriptor()
            guard libusb_get_device_descriptor(device, &descriptor) == 0 else { continue }

            if descriptor.idVendor == FELConstants.vendorID &&
               descriptor.idProduct == FELConstants.productID {
                found = true

                // Distinguish FEL from Clovershell by probing endpoint addresses.
                // FEL uses IN=0x82, Clovershell uses IN=0x81.
                let mode = identifyDeviceMode(device)
                let state: ConsoleState = (mode == .clovershell) ? .connected : .felMode

                if deviceState != state {
                    let label = (mode == .clovershell) ? "Clovershell" : "FEL"
                    HakchiLogger.usb.info("\(label) device detected (VID:\(String(format: "0x%04X", descriptor.idVendor)) PID:\(String(format: "0x%04X", descriptor.idProduct)))")
                }

                wasConnected = true
                updateState(state, type: .unknown)
                break
            }
        }

        if !found && wasConnected {
            wasConnected = false
            updateState(.disconnected, type: .unknown)
            HakchiLogger.usb.info("Device disconnected")
        }
    }

    // MARK: - Device Mode Detection

    private enum DeviceMode {
        case fel
        case clovershell
    }

    /// Probe the USB config descriptor to identify FEL vs Clovershell.
    ///
    /// FEL (BROM):       single interface, bulk IN endpoint = 0x82
    /// Clovershell (gadget): may have multiple interfaces, bulk IN endpoint = 0x81
    private func identifyDeviceMode(_ device: OpaquePointer) -> DeviceMode {
        var config: UnsafeMutablePointer<libusb_config_descriptor>?
        guard libusb_get_config_descriptor(device, 0, &config) == 0,
              let cfg = config else {
            return .fel // Default to FEL if we can't read descriptors
        }
        defer { libusb_free_config_descriptor(config) }

        // Scan all interfaces for bulk IN endpoint address
        for i in 0..<Int(cfg.pointee.bNumInterfaces) {
            let iface = cfg.pointee.interface[i]
            guard iface.num_altsetting > 0 else { continue }
            let alt = iface.altsetting[0]
            for e in 0..<Int(alt.bNumEndpoints) {
                let ep = alt.endpoint[e]
                let isBulk = (ep.bmAttributes & 0x03) == UInt8(LIBUSB_TRANSFER_TYPE_BULK.rawValue)
                let isIn = (ep.bEndpointAddress & 0x80) != 0
                if isBulk && isIn {
                    if ep.bEndpointAddress == 0x81 {
                        return .clovershell
                    } else if ep.bEndpointAddress == 0x82 {
                        return .fel
                    }
                }
            }
        }

        return .fel
    }

    private func updateState(_ state: ConsoleState, type: ConsoleType) {
        DispatchQueue.main.async { [weak self] in
            if self?.deviceState != state {
                self?.deviceState = state
            }
            if self?.detectedConsoleType != type {
                self?.detectedConsoleType = type
            }
        }
    }
}
