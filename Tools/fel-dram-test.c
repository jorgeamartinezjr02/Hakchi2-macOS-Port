// fel-dram-test.c — Load FES1, init DRAM, verify access across 128MB
// Reuses proven protocol from fel-boot.c
// Build: cc -o fel-dram-test fel-dram-test.c -I/opt/homebrew/include -I/opt/homebrew/include/libusb-1.0 -L/opt/homebrew/lib -lusb-1.0
// Usage: ./fel-dram-test ../Resources/boot/fes1.bin

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <libusb.h>

#define FEL_VID  0x1F3A
#define FEL_PID  0xEFE8
#define TIMEOUT  10000

#define AW_USB_WRITE 0x12
#define AW_USB_READ  0x11
#define FEL_VERIFY   0x001
#define FEL_DOWNLOAD 0x101
#define FEL_EXEC     0x102
#define FEL_UPLOAD   0x103
#define FES1_ADDR    0x00002000

static libusb_device_handle *handle = NULL;

/* ── USB low-level (same as fel-boot.c) ── */
static int usb_send(const void *data, int len) {
    int sent = 0;
    return libusb_bulk_transfer(handle, 0x01, (void*)data, len, &sent, TIMEOUT);
}
static int usb_recv(void *data, int len) {
    int recvd = 0;
    int rc = libusb_bulk_transfer(handle, 0x82, data, len, &recvd, TIMEOUT);
    while (rc == 0 && recvd < len) {
        int got = 0;
        rc = libusb_bulk_transfer(handle, 0x82, (uint8_t*)data + recvd,
                                  len - recvd, &got, TIMEOUT);
        if (rc != 0) break;
        recvd += got;
    }
    return rc;
}

/* ── AW USB protocol ── */
#pragma pack(push, 1)
struct aw_usb_request {
    char sig[8]; uint32_t length; uint32_t unknown1;
    uint16_t request; uint32_t length2; char pad[10];
};
#pragma pack(pop)

static int aw_send_req(int type, int length) {
    struct aw_usb_request req;
    memset(&req, 0, sizeof(req));
    memcpy(req.sig, "AWUC", 4);
    req.length = length; req.unknown1 = 0x0c000000;
    req.request = type; req.length2 = length;
    return usb_send(&req, sizeof(req));
}
static int aw_read_resp(void) { char b[13]; return usb_recv(b, 13); }

static int aw_usb_write(const void *data, int len) {
    int rc = aw_send_req(AW_USB_WRITE, len);
    if (rc) return rc;
    rc = usb_send(data, len);
    if (rc) return rc;
    return aw_read_resp();
}
static int aw_usb_read(void *data, int len) {
    int rc = aw_send_req(AW_USB_READ, len);
    if (rc) return rc;
    rc = usb_recv(data, len);
    if (rc) return rc;
    return aw_read_resp();
}

/* ── FEL commands ── */
static int fel_cmd(int cmd, uint32_t addr, uint32_t len) {
    uint32_t req[4] = { cmd, addr, len, 0 };
    return aw_usb_write(req, 16);
}
static int fel_status(void) { char b[8]; return aw_usb_read(b, 8); }

static int fel_verify(uint32_t *soc_id) {
    int rc = fel_cmd(FEL_VERIFY, 0, 0);
    if (rc) return rc;
    uint8_t ver[32]; rc = aw_usb_read(ver, 32);
    if (rc) return rc;
    rc = fel_status();
    if (soc_id) *soc_id = ((ver[8]|(ver[9]<<8)|(ver[10]<<16)|(ver[11]<<24))>>8)&0xFFFF;
    printf("  Signature: %.8s\n", ver);
    printf("  SoC ID: 0x%04X\n", soc_id ? *soc_id : 0);
    return rc;
}

static int fel_write(uint32_t addr, const void *buf, uint32_t len) {
    if (!len) return 0;
    int rc = fel_cmd(FEL_DOWNLOAD, addr, len);
    if (rc) return rc;
    rc = aw_usb_write(buf, len);
    if (rc) return rc;
    return fel_status();
}

static int fel_read(uint32_t addr, void *buf, uint32_t len) {
    int rc = fel_cmd(FEL_UPLOAD, addr, len);
    if (rc) return rc;
    rc = aw_usb_read(buf, len);
    if (rc) return rc;
    return fel_status();
}

static int fel_exec(uint32_t addr) {
    int rc = fel_cmd(FEL_EXEC, addr, 0);
    if (rc) return rc;
    return fel_status();
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <fes1.bin>\n", argv[0]);
        return 1;
    }

    /* Load FES1 */
    FILE *f = fopen(argv[1], "rb");
    if (!f) { perror("fopen"); return 1; }
    fseek(f, 0, SEEK_END);
    size_t fes1_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *fes1 = malloc(fes1_size);
    fread(fes1, 1, fes1_size, f);
    fclose(f);

    printf("=== FEL DRAM Initialization Test ===\n");
    printf("FES1: %s (%zu bytes)\n", argv[1], fes1_size);
    printf("Header: %.8s\n\n", fes1 + 4);

    if (memcmp(fes1 + 4, "eGON.BT0", 8) != 0) {
        printf("ERROR: Invalid FES1 (no eGON.BT0 header)\n");
        free(fes1); return 1;
    }

    /* Init libusb */
    int rc = libusb_init(NULL);
    if (rc) { fprintf(stderr, "libusb_init: %d\n", rc); return 1; }

    handle = libusb_open_device_with_vid_pid(NULL, FEL_VID, FEL_PID);
    if (!handle) {
        printf("ERROR: No FEL device. Hold Reset while plugging in USB.\n");
        libusb_exit(NULL); free(fes1); return 1;
    }
    if (libusb_kernel_driver_active(handle, 0) == 1)
        libusb_detach_kernel_driver(handle, 0);
    rc = libusb_claim_interface(handle, 0);
    if (rc) { fprintf(stderr, "claim: %s\n", libusb_error_name(rc)); return 1; }

    /* Step 1: Verify */
    printf("--- Step 1: Verify Device ---\n");
    uint32_t soc = 0;
    rc = fel_verify(&soc);
    if (rc) { printf("  FAILED (rc=%d)\n", rc); goto done; }
    printf("  OK\n\n");

    /* Step 2: Load FES1 */
    printf("--- Step 2: Load FES1 to 0x%08X (%zu bytes) ---\n", FES1_ADDR, fes1_size);
    rc = fel_write(FES1_ADDR, fes1, fes1_size);
    if (rc) { printf("  Write FAILED (rc=%d)\n", rc); goto done; }

    /* Verify write */
    uint8_t *verify_buf = malloc(fes1_size);
    rc = fel_read(FES1_ADDR, verify_buf, fes1_size);
    if (rc == 0 && memcmp(verify_buf, fes1, fes1_size) == 0) {
        printf("  Written & verified OK (%zu bytes match)\n\n", fes1_size);
    } else {
        printf("  VERIFY FAILED\n");
        free(verify_buf); goto done;
    }
    free(verify_buf);

    /* Step 3: Execute FES1 */
    printf("--- Step 3: Execute FES1 (DRAM init) ---\n");
    rc = fel_exec(FES1_ADDR);
    if (rc) { printf("  FAILED (rc=%d). Power-cycle console.\n", rc); goto done; }
    printf("  FES1 executed.\n");
    printf("  Waiting 2s for DRAM init...\n");
    usleep(2000000);

    /* Re-verify device after FES1 (it may re-enumerate) */
    rc = fel_verify(&soc);
    if (rc) {
        printf("  Device unresponsive, reconnecting...\n");
        libusb_release_interface(handle, 0);
        libusb_close(handle);
        handle = NULL;
        usleep(2000000);
        for (int i = 0; i < 30; i++) {
            handle = libusb_open_device_with_vid_pid(NULL, FEL_VID, FEL_PID);
            if (handle) break;
            usleep(1000000);
        }
        if (!handle) { printf("  Lost device.\n"); goto done; }
        if (libusb_kernel_driver_active(handle, 0) == 1)
            libusb_detach_kernel_driver(handle, 0);
        libusb_claim_interface(handle, 0);
        rc = fel_verify(&soc);
        if (rc) { printf("  Still failed after reconnect.\n"); goto done; }
    }
    printf("  Device responsive after DRAM init.\n\n");

    /* Step 4: DRAM verification */
    printf("--- Step 4: DRAM Verification ---\n");

    struct { uint32_t addr; const char *desc; } tests[] = {
        { 0x40000000, "base" },
        { 0x40001000, "+4KB" },
        { 0x40010000, "+64KB" },
        { 0x40100000, "+1MB" },
        { 0x41000000, "+16MB" },
        { 0x42000000, "+32MB" },
        { 0x43000000, "+48MB" },
        { 0x44000000, "+64MB" },
        { 0x45000000, "+80MB" },
        { 0x46000000, "+96MB" },
        { 0x47000000, "+112MB" },
        { 0x47F00000, "+127MB" },
    };
    int num_tests = sizeof(tests) / sizeof(tests[0]);
    int pass = 0;

    for (int i = 0; i < num_tests; i++) {
        uint32_t addr = tests[i].addr;
        uint32_t pattern = addr ^ 0xDEADBEEF;
        uint32_t readback = 0;

        rc = fel_write(addr, &pattern, 4);
        if (rc) { printf("  0x%08X %-8s WRITE FAIL (rc=%d)\n", addr, tests[i].desc, rc); continue; }

        rc = fel_read(addr, &readback, 4);
        if (rc) { printf("  0x%08X %-8s READ FAIL (rc=%d)\n", addr, tests[i].desc, rc); continue; }

        int ok = (readback == pattern);
        printf("  0x%08X %-8s wrote=0x%08X read=0x%08X %s\n",
               addr, tests[i].desc, pattern, readback, ok ? "PASS" : "FAIL");
        if (ok) pass++;
    }

    printf("\n=== Result: %d/%d DRAM regions accessible ===\n", pass, num_tests);
    if (pass == num_tests)
        printf("SUCCESS: 128MB DRAM fully initialized!\n");
    else if (pass > 0)
        printf("PARTIAL: Some DRAM accessible.\n");
    else
        printf("FAILED: No DRAM accessible.\n");

done:
    if (handle) {
        libusb_release_interface(handle, 0);
        libusb_close(handle);
    }
    libusb_exit(NULL);
    free(fes1);
    return 0;
}
