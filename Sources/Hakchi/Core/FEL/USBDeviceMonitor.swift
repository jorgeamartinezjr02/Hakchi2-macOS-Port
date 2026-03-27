import Foundation
import Combine
import CLibUSB

final class USBDeviceMonitor: ObservableObject {
    @Published var deviceState: ConsoleState = .disconnected
    @Published var detectedConsoleType: ConsoleType = .unknown

    private var monitorTimer: Timer?
    private var context: OpaquePointer?
    private var isMonitoring = false

    deinit {
        stopMonitoring()
    }

    func startMonitoring() {
        guard !isMonitoring else { return }
        isMonitoring = true

        var ctx: OpaquePointer?
        if libusb_init(&ctx) == 0 {
            context = ctx
        }

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

        if let ctx = context {
            libusb_exit(ctx)
            context = nil
        }

        HakchiLogger.usb.info("USB device monitoring stopped")
    }

    private func checkForDevice() {
        guard let ctx = context else { return }

        var deviceList: UnsafeMutablePointer<OpaquePointer?>?
        let count = libusb_get_device_list(ctx, &deviceList)

        defer {
            if let list = deviceList {
                libusb_free_device_list(list, 1)
            }
        }

        guard count > 0, let list = deviceList else {
            updateState(.disconnected, type: .unknown)
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
                updateState(.felMode, type: .unknown)
                HakchiLogger.usb.info("FEL device detected (VID:\(String(format: "0x%04X", descriptor.idVendor)) PID:\(String(format: "0x%04X", descriptor.idProduct)))")
                break
            }
        }

        if !found && deviceState != .disconnected {
            updateState(.disconnected, type: .unknown)
            HakchiLogger.usb.info("FEL device disconnected")
        }
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
