/*
 * clover-exec.c — Execute commands on hakchi console via Clovershell USB protocol
 *
 * Protocol reverse-engineered from TeamShinkansen/Hakchi2-CE ClovershellConnection.cs
 *
 * Build:
 *   cc -std=c99 -Wall -O2 \
 *     -I/opt/homebrew/include -I/opt/homebrew/include/libusb-1.0 \
 *     -o clover-exec clover-exec.c -L/opt/homebrew/lib -lusb-1.0
 *
 * Usage:
 *   sudo ./clover-exec "command"
 *   sudo ./clover-exec -o out.bin "dd if=/dev/mtd2 bs=64k"
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <libusb.h>

/* Clovershell USB device — VID/PID set by f_clovershell() in ramdisk */
#define CS_VID  0x1F3A
#define CS_PID  0xEFE8
#define TIMEOUT 10000
#define BUF_SIZE 65536

/* Clovershell commands (from ClovershellConnection.cs) */
#define CMD_PING              0
#define CMD_PONG              1
#define CMD_SHELL_NEW_REQ     2
#define CMD_SHELL_NEW_RESP    3
#define CMD_SHELL_IN          4
#define CMD_SHELL_OUT         5
#define CMD_SHELL_CLOSED      6
#define CMD_SHELL_KILL        7
#define CMD_SHELL_KILL_ALL    8
#define CMD_EXEC_NEW_REQ      9
#define CMD_EXEC_NEW_RESP    10
#define CMD_EXEC_PID         11
#define CMD_EXEC_STDIN       12
#define CMD_EXEC_STDOUT      13
#define CMD_EXEC_STDERR      14
#define CMD_EXEC_RESULT      15
#define CMD_EXEC_KILL        16
#define CMD_EXEC_KILL_ALL    17

static libusb_device_handle *handle = NULL;
static uint8_t ep_out = 0x01, ep_in = 0x81;

/* ── Raw USB I/O ─────────────────────────────────────────── */
static int usb_write(const void *data, int len) {
    int sent = 0;
    return libusb_bulk_transfer(handle, ep_out, (void *)data, len, &sent, 1000);
}

static int usb_read(void *data, int len, int *actual, int timeout_ms) {
    *actual = 0;
    return libusb_bulk_transfer(handle, ep_in, data, len, actual, timeout_ms);
}

/* ── Send a Clovershell packet (header + payload as one transfer) ── */
static int cs_send(uint8_t cmd, uint8_t arg, const void *data, uint16_t len) {
    uint8_t *pkt = malloc(4 + len);
    if (!pkt) return -1;
    pkt[0] = cmd;
    pkt[1] = arg;
    pkt[2] = (uint8_t)(len & 0xFF);
    pkt[3] = (uint8_t)(len >> 8);
    if (len > 0 && data) memcpy(pkt + 4, data, len);
    int rc = usb_write(pkt, 4 + len);
    free(pkt);
    return rc;
}

/* ── Receive buffer (handles multiple packets per USB transfer) ── */
static uint8_t recv_buf[BUF_SIZE];
static int recv_pos = 0;
static int recv_count = 0;

/* Fill recv buffer from USB if empty */
static int recv_fill(int timeout_ms) {
    if (recv_pos < recv_count) return 0; /* still have data */
    recv_pos = 0;
    recv_count = 0;
    int got = 0;
    int rc = usb_read(recv_buf, BUF_SIZE, &got, timeout_ms);
    if (rc == 0 || rc == LIBUSB_ERROR_OVERFLOW) {
        recv_count = got;
        return (got > 0) ? 0 : -1;
    }
    return rc;
}

/* Parse next packet from recv buffer.
 * Returns 0 on success, fills cmd/arg/payload/len.
 * payload points into recv_buf — valid until next recv_fill. */
static int cs_recv(uint8_t *cmd, uint8_t *arg, uint8_t **payload, uint16_t *len,
                   int timeout_ms) {
    int rc = recv_fill(timeout_ms);
    if (rc) return rc;

    int avail = recv_count - recv_pos;
    if (avail < 4) return -1; /* incomplete header */

    *cmd = recv_buf[recv_pos];
    *arg = recv_buf[recv_pos + 1];
    *len = recv_buf[recv_pos + 2] | (recv_buf[recv_pos + 3] << 8);
    recv_pos += 4;

    if (*len > 0) {
        if (recv_pos + *len > recv_count) {
            /* Payload split across transfers — shouldn't happen with 64K buffer
             * but handle it by copying remaining and reading more */
            int have = recv_count - recv_pos;
            static uint8_t split_buf[BUF_SIZE];
            if (have > 0) memcpy(split_buf, recv_buf + recv_pos, have);
            int need = *len - have;
            while (need > 0) {
                int got = 0;
                rc = usb_read(split_buf + have, need, &got, timeout_ms);
                if (rc && rc != LIBUSB_ERROR_OVERFLOW) return rc;
                have += got;
                need -= got;
            }
            *payload = split_buf;
            recv_pos = recv_count; /* consumed everything */
        } else {
            *payload = recv_buf + recv_pos;
            recv_pos += *len;
        }
    } else {
        *payload = NULL;
    }
    return 0;
}

/* ── Detect endpoints from device descriptor ─────────────── */
static int find_endpoints(void) {
    libusb_device *dev = libusb_get_device(handle);
    struct libusb_config_descriptor *config;
    int rc = libusb_get_config_descriptor(dev, 0, &config);
    if (rc) return rc;

    int found_in = 0, found_out = 0;
    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface_descriptor *iface =
            &config->interface[i].altsetting[0];
        for (int e = 0; e < iface->bNumEndpoints; e++) {
            const struct libusb_endpoint_descriptor *ep = &iface->endpoint[e];
            /* Only look at bulk endpoints */
            if ((ep->bmAttributes & 0x03) != LIBUSB_TRANSFER_TYPE_BULK)
                continue;
            uint8_t addr = ep->bEndpointAddress;
            if ((addr & 0x80) && addr == 0x81) { ep_in = addr; found_in = 1; }
            if (!(addr & 0x80) && addr == 0x01) { ep_out = addr; found_out = 1; }
        }
    }
    libusb_free_config_descriptor(config);
    fprintf(stderr, "  Endpoints: OUT=0x%02X IN=0x%02X\n", ep_out, ep_in);
    return (found_in && found_out) ? 0 : -1;
}

/* ── Print device descriptor info ────────────────────────── */
static void print_device_info(void) {
    libusb_device *dev = libusb_get_device(handle);
    struct libusb_config_descriptor *config;
    if (libusb_get_config_descriptor(dev, 0, &config)) return;

    fprintf(stderr, "  Config %d: %d interfaces\n",
            config->bConfigurationValue, config->bNumInterfaces);
    for (int i = 0; i < config->bNumInterfaces; i++) {
        const struct libusb_interface_descriptor *iface =
            &config->interface[i].altsetting[0];
        fprintf(stderr, "  Interface %d: class=%d, %d endpoints\n",
                iface->bInterfaceNumber, iface->bInterfaceClass,
                iface->bNumEndpoints);
        for (int e = 0; e < iface->bNumEndpoints; e++) {
            const struct libusb_endpoint_descriptor *ep = &iface->endpoint[e];
            fprintf(stderr, "    EP 0x%02X: %s, type=%d, maxpkt=%d\n",
                    ep->bEndpointAddress,
                    (ep->bEndpointAddress & 0x80) ? "IN" : "OUT",
                    ep->bmAttributes & 0x03,
                    ep->wMaxPacketSize);
        }
    }
    libusb_free_config_descriptor(config);
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    setbuf(stderr, NULL);

    const char *command = NULL;
    const char *outfile = NULL;

    for (int i = 1; i < argc; i++) {
        if (strcmp(argv[i], "-o") == 0 && i + 1 < argc)
            outfile = argv[++i];
        else
            command = argv[i];
    }

    if (!command) {
        fprintf(stderr, "Usage: %s [-o outfile] \"command\"\n", argv[0]);
        return 1;
    }

    int rc = libusb_init(NULL);
    if (rc) { fprintf(stderr, "libusb_init: %d\n", rc); return 1; }

    /* ── Find device (wait up to 30s) ─────────────────────── */
    fprintf(stderr, "Looking for Clovershell device (%04X:%04X)...\n", CS_VID, CS_PID);
    for (int i = 0; i < 30; i++) {
        handle = libusb_open_device_with_vid_pid(NULL, CS_VID, CS_PID);
        if (handle) break;
        usleep(1000000);
    }
    if (!handle) { fprintf(stderr, "Device not found\n"); return 1; }
    fprintf(stderr, "Device found!\n");

    libusb_set_auto_detach_kernel_driver(handle, 1);
    print_device_info();

    /* ── Claim interfaces ─────────────────────────────────── */
    /* C# claims interface 0 only, but on macOS we need to claim the interface
     * that has the bulk endpoints (interface 1 on this device).
     * Try claiming both — if 0 fails that's okay. */
    /* Claim all available interfaces (Clovershell may use iface 0 or 1) */
    {
        libusb_device *dev = libusb_get_device(handle);
        struct libusb_config_descriptor *cfg;
        if (libusb_get_config_descriptor(dev, 0, &cfg) == 0) {
            for (int i = 0; i < cfg->bNumInterfaces; i++) {
                rc = libusb_claim_interface(handle, i);
                if (rc)
                    fprintf(stderr, "  claim iface %d: %d (%s)\n", i, rc, libusb_strerror(rc));
                else
                    fprintf(stderr, "  Interface %d claimed\n", i);
            }
            libusb_free_config_descriptor(cfg);
        }
    }

    if (find_endpoints() != 0) {
        fprintf(stderr, "  Using default endpoints 0x01/0x81\n");
        ep_out = 0x01;
        ep_in = 0x81;
    }

    /* ── Init sequence (matches C# ClovershellConnection) ── */

    /* Step 1: Kill all existing sessions FIRST (C# does this before drain) */
    fprintf(stderr, "Killing existing sessions...\n");
    uint8_t kill_shell[4] = { CMD_SHELL_KILL_ALL, 0, 0, 0 };
    uint8_t kill_exec[4]  = { CMD_EXEC_KILL_ALL,  0, 0, 0 };
    int dummy;
    libusb_bulk_transfer(handle, ep_out, kill_shell, 4, &dummy, 1000);
    libusb_bulk_transfer(handle, ep_out, kill_exec, 4, &dummy, 1000);

    /* Step 2: Drain any pending data (C# uses 50ms timeout) */
    fprintf(stderr, "Draining pending data...\n");
    for (int d = 0; d < 20; d++) {
        uint8_t drain[BUF_SIZE];
        int got = 0;
        int drc = libusb_bulk_transfer(handle, ep_in, drain, BUF_SIZE, &got, 100);
        if (got > 0) {
            fprintf(stderr, "  Drained %d bytes (first 4: %02X %02X %02X %02X)\n",
                    got,
                    drain[0], got > 1 ? drain[1] : 0,
                    got > 2 ? drain[2] : 0, got > 3 ? drain[3] : 0);
        }
        if (drc == LIBUSB_ERROR_TIMEOUT && got == 0) break;
    }

    /* Step 3: Quick PING to verify daemon is alive */
    fprintf(stderr, "Sending PING...\n");
    rc = cs_send(CMD_PING, 0, NULL, 0);
    if (rc) {
        fprintf(stderr, "  PING send failed: %d\n", rc);
        return 1;
    }

    /* Wait for PONG (the daemon should respond quickly) */
    {
        uint8_t pcmd, parg;
        uint8_t *pdata;
        uint16_t plen;
        rc = cs_recv(&pcmd, &parg, &pdata, &plen, 3000);
        if (rc == LIBUSB_ERROR_TIMEOUT) {
            fprintf(stderr, "  No PONG — Clovershell daemon may not be running\n");
            fprintf(stderr, "  (The boot.img ramdisk might not include the daemon)\n");
            return 1;
        }
        if (rc) {
            fprintf(stderr, "  PONG recv error: %d\n", rc);
            return 1;
        }
        if (pcmd == CMD_PONG)
            fprintf(stderr, "  PONG received — daemon is alive!\n");
        else
            fprintf(stderr, "  Got cmd=%d (expected PONG=%d) — continuing\n", pcmd, CMD_PONG);
    }

    /* ── Execute command ──────────────────────────────────── */
    fprintf(stderr, "Executing: %s\n", command);
    rc = cs_send(CMD_EXEC_NEW_REQ, 0, command, strlen(command));
    if (rc) { fprintf(stderr, "send exec: %d\n", rc); return 1; }

    /* Open output file if requested */
    FILE *out = stdout;
    if (outfile) {
        out = fopen(outfile, "wb");
        if (!out) { perror(outfile); return 1; }
    }

    /* ── Read responses ───────────────────────────────────── */
    uint8_t cmd, arg;
    uint8_t *payload;
    uint16_t len;
    int session_id = -1;
    int exit_code = -1;
    int done = 0;
    int stdout_done = 0;

    while (!done) {
        rc = cs_recv(&cmd, &arg, &payload, &len, TIMEOUT);
        if (rc) {
            if (rc == LIBUSB_ERROR_TIMEOUT) {
                cs_send(CMD_PING, 0, NULL, 0);
                continue;
            }
            fprintf(stderr, "recv error: %d (%s)\n", rc, libusb_strerror(rc));
            break;
        }

        switch (cmd) {
        case CMD_EXEC_NEW_RESP:
            session_id = arg;
            fprintf(stderr, "Session ID: %d\n", session_id);
            /* Close stdin immediately (no input needed) */
            cs_send(CMD_EXEC_STDIN, session_id, NULL, 0);
            break;

        case CMD_EXEC_STDOUT:
            if (len == 0) {
                stdout_done = 1;
                if (exit_code >= 0) done = 1;
            } else {
                fwrite(payload, 1, len, out);
            }
            break;

        case CMD_EXEC_STDERR:
            if (len > 0)
                fwrite(payload, 1, len, stderr);
            break;

        case CMD_EXEC_RESULT:
            exit_code = (len > 0) ? payload[0] : 0;
            fprintf(stderr, "Exit code: %d\n", exit_code);
            if (stdout_done) done = 1;
            break;

        case CMD_EXEC_PID:
        case CMD_PONG:
        case CMD_EXEC_STDIN: /* flow control echo, ignore */
            break;

        default:
            fprintf(stderr, "Unknown cmd: %d arg=%d len=%d\n", cmd, arg, len);
            break;
        }
    }

    if (outfile && out != stdout)
        fclose(out);

    /* Release all claimed interfaces */
    {
        libusb_device *dev = libusb_get_device(handle);
        struct libusb_config_descriptor *cfg;
        if (libusb_get_config_descriptor(dev, 0, &cfg) == 0) {
            for (int i = cfg->bNumInterfaces - 1; i >= 0; i--)
                libusb_release_interface(handle, i);
            libusb_free_config_descriptor(cfg);
        }
    }
    libusb_close(handle);
    libusb_exit(NULL);

    return exit_code >= 0 ? exit_code : 1;
}
