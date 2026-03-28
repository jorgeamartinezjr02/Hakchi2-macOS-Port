/*
 * fel-boot.c — Hakchi FEL memboot (matching hakchi2-CE's actual boot flow)
 *
 * Flow: FES1 → DRAM init → boot.img to 0x47400000 → U-Boot to 0x47000000
 *       → patch bootcmd → execute U-Boot → kernel boots from RAM
 *
 * Build:
 *   cc -std=c99 -Wall -O2 \
 *     -I/opt/homebrew/include -I/opt/homebrew/include/libusb-1.0 \
 *     -o fel-boot fel-boot.c -L/opt/homebrew/lib -lusb-1.0
 *
 * Usage: ./fel-boot <fes1.bin> <uboot.bin> <boot.img>
 */

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

/* hakchi2-CE memory map */
#define FES1_ADDR      0x00002000
#define UBOOT_ADDR     0x47000000
#define TRANSFER_ADDR  0x47400000

static libusb_device_handle *handle = NULL;

/* ── USB low-level ──────────────────────────────────────── */
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

/* ── AW USB protocol (32-byte AWUC/13-byte AWUS) ─────── */
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

/* ── FEL commands ────────────────────────────────────────── */
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

/* Write large buffer with progress (64KB chunks) */
static int fel_write_large(uint32_t addr, const uint8_t *buf, uint32_t total, const char *label) {
    const uint32_t chunk = 0x10000; /* 64KB like hakchi2-CE */
    uint32_t off = 0;
    while (off < total) {
        uint32_t n = (total - off < chunk) ? total - off : chunk;
        int rc = fel_write(addr + off, buf + off, n);
        if (rc) {
            fprintf(stderr, "\n  Write failed at 0x%X: rc=%d\n", addr+off, rc);
            return rc;
        }
        off += n;
        printf("\r  %s: %u / %u KB", label, off/1024, total/1024);
        fflush(stdout);
    }
    printf("\n");
    return 0;
}

/* ── File I/O ────────────────────────────────────────────── */
static uint8_t *read_file(const char *path, size_t *size) {
    FILE *f = fopen(path, "rb");
    if (!f) { perror(path); return NULL; }
    fseek(f, 0, SEEK_END); *size = ftell(f); fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc(*size);
    fread(buf, 1, *size, f); fclose(f);
    return buf;
}

/* ── Main ────────────────────────────────────────────────── */
int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    if (argc < 4) {
        fprintf(stderr, "Usage: %s <fes1.bin> <uboot.bin> <boot.img>\n", argv[0]);
        return 1;
    }

    size_t fes1_size, uboot_size, boot_size;
    uint8_t *fes1  = read_file(argv[1], &fes1_size);
    uint8_t *uboot = read_file(argv[2], &uboot_size);
    uint8_t *boot  = read_file(argv[3], &boot_size);
    if (!fes1 || !uboot || !boot) return 1;

    printf("Files: fes1=%zuB uboot=%zuB boot.img=%zuB\n",
           fes1_size, uboot_size, boot_size);

    /* Find bootcmd= in uboot */
    int cmd_offset = -1;
    for (size_t i = 0; i < uboot_size - 8; i++) {
        if (memcmp(uboot + i, "bootcmd=", 8) == 0) {
            cmd_offset = (int)i;
            break;
        }
    }
    if (cmd_offset < 0) {
        fprintf(stderr, "ERROR: bootcmd= not found in uboot.bin\n");
        return 1;
    }
    printf("bootcmd at offset 0x%X: %.60s\n", cmd_offset, uboot + cmd_offset);

    /* Init libusb */
    int rc = libusb_init(NULL); /* use default context like sunxi-fel */
    if (rc) { fprintf(stderr, "libusb_init: %d\n", rc); return 1; }

    /* ── Step 1: Connect ────────────────────────────────── */
    printf("\n[1/6] Connecting to FEL device...\n");
    for (int i = 0; i < 60; i++) {
        handle = libusb_open_device_with_vid_pid(NULL, FEL_VID, FEL_PID);
        if (handle) break;
        if (i == 0) printf("  Waiting...\n");
        usleep(1000000);
    }
    if (!handle) { fprintf(stderr, "No FEL device\n"); return 1; }

    if (libusb_kernel_driver_active(handle, 0) == 1)
        libusb_detach_kernel_driver(handle, 0);
    rc = libusb_claim_interface(handle, 0);
    if (rc) { fprintf(stderr, "claim: %d\n", rc); return 1; }

    uint32_t soc = 0;
    rc = fel_verify(&soc);
    if (rc) { fprintf(stderr, "verify: %d\n", rc); return 1; }
    printf("  SoC: 0x%04X\n", soc);

    /* ── Step 2: DRAM init via FES1 ─────────────────────── */
    printf("\n[2/6] Loading FES1 to SRAM at 0x%X (%zu bytes)...\n", FES1_ADDR, fes1_size);
    rc = fel_write(FES1_ADDR, fes1, fes1_size);
    if (rc) { fprintf(stderr, "FES1 write failed: %d\n", rc); return 1; }
    printf("  FES1 written\n");

    printf("  Executing FES1 (DRAM init)...\n");
    rc = fel_exec(FES1_ADDR);
    if (rc) { fprintf(stderr, "FES1 exec failed: %d\n", rc); return 1; }

    printf("  Waiting 2s for DRAM init...\n");
    usleep(2000000);

    /* Verify device is still responsive */
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
        if (!handle) { fprintf(stderr, "Lost device after FES1\n"); return 1; }
        if (libusb_kernel_driver_active(handle, 0) == 1)
            libusb_detach_kernel_driver(handle, 0);
        libusb_claim_interface(handle, 0);
        rc = fel_verify(&soc);
        if (rc) { fprintf(stderr, "Verify after FES1 reconnect: %d\n", rc); return 1; }
    }
    printf("  DRAM initialized ✓\n");

    /* Quick DRAM test */
    uint32_t test = 0xDEADBEEF, readback = 0;
    fel_write(0x40000100, &test, 4);
    fel_read(0x40000100, &readback, 4);
    printf("  DRAM test: 0x%08X %s\n", readback,
           readback == 0xDEADBEEF ? "✓" : "FAIL");

    /* ── Step 3: Write boot.img to transfer buffer ──────── */
    printf("\n[3/6] Loading boot.img to 0x%08X...\n", TRANSFER_ADDR);
    rc = fel_write_large(TRANSFER_ADDR, boot, boot_size, "boot.img");
    if (rc) return 1;

    /* ── Step 4: Write U-Boot to DRAM ───────────────────── */
    printf("\n[4/6] Loading U-Boot to 0x%08X...\n", UBOOT_ADDR);

    /* Patch bootcmd to set bootargs (with hakchi-clovershell) then boot from RAM.
     * Without explicit setenv, U-Boot loads bootargs from NAND env and ignores
     * the boot.img cmdline — clovershell never starts. */
    const char *new_cmd =
        "setenv bootargs root=/dev/nandb decrypt ro console=ttyS0,115200 loglevel=4 "
        "ion_cma_512m=16m coherent_pool=4m consoleblank=0 "
        "hakchi-clovershell hakchi-memboot; boota 47400000";
    size_t new_len = strlen(new_cmd);
    /* Find end of original bootcmd string */
    size_t orig_end = cmd_offset + 8;
    while (orig_end < uboot_size && uboot[orig_end] != '\0') orig_end++;
    size_t orig_len = orig_end - (cmd_offset + 8);
    /* Write new command, ensuring it fits */
    if (new_len > orig_len + 64) {
        fprintf(stderr, "WARNING: new bootcmd longer than available space, truncating\n");
        new_len = orig_len;
    }
    memcpy(uboot + cmd_offset + 8, new_cmd, new_len);
    /* Null-terminate and zero out remainder */
    for (size_t i = cmd_offset + 8 + new_len; i <= orig_end; i++)
        uboot[i] = '\0';

    printf("  Patched bootcmd: %.120s\n", uboot + cmd_offset);

    rc = fel_write_large(UBOOT_ADDR, uboot, uboot_size, "U-Boot");
    if (rc) return 1;

    /* ── Step 5: Execute U-Boot ─────────────────────────── */
    printf("\n[5/6] Executing U-Boot at 0x%08X...\n", UBOOT_ADDR);
    rc = fel_exec(UBOOT_ADDR);
    if (rc) {
        fprintf(stderr, "U-Boot exec failed: %d\n", rc);
        return 1;
    }
    printf("  U-Boot started → booting kernel from RAM...\n");
    printf("  Kernel is booting with hakchi-clovershell enabled.\n");
    printf("  Use clover-exec to communicate with the console.\n");

    /* Release USB */
    libusb_release_interface(handle, 0);
    libusb_close(handle);
    libusb_exit(NULL);

    return 0;
}
