// sync-test.c — Test game sync pipeline: CRC32, CLV code, .desktop, upload via Clovershell
// Build: cc -std=c99 -Wall -O2 -I/opt/homebrew/include -I/opt/homebrew/include/libusb-1.0 -o sync-test sync-test.c -L/opt/homebrew/lib -lusb-1.0
// Usage: ./sync-test <rom-file>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <libusb.h>

/* ── CRC32 (matching hakchi2-CE) ── */
static uint32_t crc32_table[256];
static void crc32_init(void) {
    for (int i = 0; i < 256; i++) {
        uint32_t c = i;
        for (int j = 0; j < 8; j++)
            c = (c >> 1) ^ (c & 1 ? 0xEDB88320 : 0);
        crc32_table[i] = c;
    }
}
static uint32_t crc32_calc(const uint8_t *data, size_t len) {
    uint32_t crc = 0xFFFFFFFF;
    for (size_t i = 0; i < len; i++)
        crc = (crc >> 8) ^ crc32_table[(crc ^ data[i]) & 0xFF];
    return crc ^ 0xFFFFFFFF;
}

/* ── CLV code generation (matching Swift Game.generateCLVCode) ── */
static void generate_clv(const char *prefix, uint32_t crc, char *out) {
    char c0 = 'A' + (crc % 26); crc >>= 5;
    char c1 = 'A' + (crc % 26); crc >>= 5;
    char c2 = 'A' + (crc % 26); crc >>= 5;
    char c3 = 'A' + (crc % 26); crc >>= 5;
    char c4 = 'A' + (crc % 26);
    sprintf(out, "%s-%c%c%c%c%c", prefix, c0, c1, c2, c3, c4);
}

/* ── Clovershell protocol (minimal, from clover-exec.c) ── */
#define CS_VID 0x1F3A
#define CS_PID 0xEFE8
#define TIMEOUT 10000
#define CMD_PING          0
#define CMD_PONG          1
#define CMD_EXEC_NEW_REQ  9
#define CMD_EXEC_NEW_RESP 10
#define CMD_EXEC_PID      11
#define CMD_EXEC_STDIN    12
#define CMD_EXEC_STDOUT   13
#define CMD_EXEC_STDERR   14
#define CMD_EXEC_RESULT   15
#define CMD_EXEC_KILL_ALL 17

static libusb_device_handle *handle;
static uint8_t ep_out = 0x01, ep_in = 0x81;

static int usb_write(const void *data, int len) {
    int sent = 0;
    return libusb_bulk_transfer(handle, ep_out, (void *)data, len, &sent, 1000);
}
static int usb_read(void *data, int len, int *actual, int timeout_ms) {
    *actual = 0;
    return libusb_bulk_transfer(handle, ep_in, data, len, actual, timeout_ms);
}

static int cs_send(uint8_t cmd, uint8_t arg, const void *payload, uint16_t len) {
    uint8_t *pkt = malloc(4 + len);
    pkt[0] = cmd; pkt[1] = arg;
    pkt[2] = len & 0xFF; pkt[3] = (len >> 8) & 0xFF;
    if (len > 0 && payload) memcpy(pkt + 4, payload, len);
    int rc = usb_write(pkt, 4 + len);
    free(pkt);
    return rc;
}

// Execute a command and capture stdout
static int cs_exec(const char *cmd, char *out, int out_size, int *exit_code) {
    uint8_t buf[65536];
    int actual;

    // Kill existing sessions
    cs_send(CMD_EXEC_KILL_ALL, 0, NULL, 0);
    usleep(50000);
    // Drain
    while (usb_read(buf, sizeof(buf), &actual, 100) == 0 && actual > 0);

    // Ping
    cs_send(CMD_PING, 0, NULL, 0);
    usb_read(buf, sizeof(buf), &actual, 2000);
    if (actual < 4 || buf[0] != CMD_PONG) return -1;

    // Exec request
    uint8_t session = 0;
    cs_send(CMD_EXEC_NEW_REQ, session, cmd, strlen(cmd));

    // Collect output
    int out_pos = 0;
    *exit_code = -1;
    int done = 0;
    int max_wait = 300; // 30 seconds max

    while (!done && max_wait-- > 0) {
        int rc = usb_read(buf, sizeof(buf), &actual, 100);
        if (rc != 0 || actual < 4) continue;

        uint8_t resp_cmd = buf[0];
        // uint8_t resp_arg = buf[1];
        uint16_t resp_len = buf[2] | (buf[3] << 8);

        switch (resp_cmd) {
        case CMD_EXEC_NEW_RESP:
        case CMD_EXEC_PID:
            break;
        case CMD_EXEC_STDOUT:
            if (resp_len > 0 && out_pos + resp_len < out_size) {
                memcpy(out + out_pos, buf + 4, resp_len);
                out_pos += resp_len;
            }
            break;
        case CMD_EXEC_STDERR:
            // Print stderr to our stderr
            if (resp_len > 0) fwrite(buf + 4, 1, resp_len, stderr);
            break;
        case CMD_EXEC_RESULT:
            if (resp_len >= 4)
                *exit_code = buf[4] | (buf[5] << 8) | (buf[6] << 16) | (buf[7] << 24);
            else
                *exit_code = 0;
            done = 1;
            break;
        }
    }
    out[out_pos] = '\0';
    return done ? 0 : -2;
}

// Write stdin to a running exec session (for file upload via tar)
static int cs_exec_stdin(uint8_t session, const void *data, int len) {
    return cs_send(CMD_EXEC_STDIN, session, data, len);
}

int main(int argc, char **argv) {
    setbuf(stdout, NULL);
    crc32_init();

    if (argc < 2) {
        fprintf(stderr, "Usage: %s <rom-file>\n", argv[0]);
        return 1;
    }

    /* ── Step 1: Load ROM and compute CRC32 ── */
    printf("=== Game Sync Test ===\n\n");
    const char *rom_path = argv[1];
    FILE *f = fopen(rom_path, "rb");
    if (!f) { perror("fopen"); return 1; }
    fseek(f, 0, SEEK_END);
    size_t rom_size = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *rom_data = malloc(rom_size);
    fread(rom_data, 1, rom_size, f);
    fclose(f);

    // Strip SMC header if present (512 bytes, file size % 1024 == 512)
    uint8_t *crc_data = rom_data;
    size_t crc_size = rom_size;
    if (rom_size % 1024 == 512 && rom_size > 512) {
        printf("  SMC header detected (512 bytes), stripping for CRC32\n");
        crc_data = rom_data + 512;
        crc_size = rom_size - 512;
    }

    uint32_t crc = crc32_calc(crc_data, crc_size);
    printf("  ROM: %s\n", rom_path);
    printf("  Size: %zu bytes (CRC data: %zu bytes)\n", rom_size, crc_size);
    printf("  CRC32: %08X\n", crc);

    /* ── Step 2: Generate CLV code ── */
    // Super Famicom Mini uses CLV-S prefix
    char clv_code[16];
    generate_clv("CLV-S", crc, clv_code);
    printf("  CLV code: %s\n\n", clv_code);

    /* ── Step 3: Generate .desktop file ── */
    // Extract filename without path/extension
    const char *basename = strrchr(rom_path, '/');
    basename = basename ? basename + 1 : rom_path;
    char game_name[256];
    strncpy(game_name, basename, sizeof(game_name));
    char *dot = strrchr(game_name, '.');
    if (dot) *dot = '\0';
    // Clean up common ROM naming: remove (U), [!], etc
    char clean_name[256] = "Super Mario World"; // Known game

    char desktop[4096];
    snprintf(desktop, sizeof(desktop),
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Exec=/usr/bin/clover-canoe-shvc-wr -rom /usr/share/games/%s/%s.sfc --volume 100 -rollback-snapshot-period 600\n"
        "Path=/var/lib/clover/profiles/0/%s/\n"
        "Name=%s\n"
        "Icon=/usr/share/games/%s/%s.png\n"
        "\n"
        "[X-CLOVER Game]\n"
        "Code=%s\n"
        "TestID=777\n"
        "ID=0\n"
        "Players=1\n"
        "Simultaneous=0\n"
        "ReleaseDate=1990-11-21\n"
        "SaveCount=0\n"
        "SortRawTitle=%s\n"
        "SortRawPublisher=Nintendo\n"
        "Copyright=Nintendo 1990\n"
        "\n"
        "[m2engage]\n"
        "Exec=/usr/bin/clover-canoe-shvc-wr -rom /usr/share/games/%s/%s.sfc --volume 100 -rollback-snapshot-period 600\n",
        clv_code, clv_code, clv_code, clean_name, clv_code, clv_code,
        clv_code, clean_name, clv_code, clv_code);

    printf("--- .desktop file ---\n%s---\n\n", desktop);

    /* ── Step 4: Connect to console via Clovershell ── */
    printf("--- Connecting to console ---\n");
    int rc = libusb_init(NULL);
    if (rc) { fprintf(stderr, "libusb_init: %d\n", rc); return 1; }

    handle = libusb_open_device_with_vid_pid(NULL, CS_VID, CS_PID);
    if (!handle) {
        printf("ERROR: Console not connected or not in Clovershell mode.\n");
        libusb_exit(NULL); return 1;
    }
    if (libusb_kernel_driver_active(handle, 0) == 1)
        libusb_detach_kernel_driver(handle, 0);
    libusb_claim_interface(handle, 0);
    printf("  Connected!\n");

    char out[65536];
    int exit_code;

    /* ── Step 5: Create game directory on console ── */
    char cmd[1024];
    const char *games_path = "/var/lib/hakchi/games/snes-jpn";

    printf("\n--- Preparing console ---\n");

    // Check if data partition is mounted
    snprintf(cmd, sizeof(cmd), "mount | grep nandc");
    cs_exec(cmd, out, sizeof(out), &exit_code);
    if (strlen(out) == 0) {
        printf("  Mounting data partition...\n");
        snprintf(cmd, sizeof(cmd), "mount -t ext4 /dev/nandc /var/lib/hakchi 2>&1 || mount -t vfat /dev/nandc /var/lib/hakchi 2>&1");
        cs_exec(cmd, out, sizeof(out), &exit_code);
        printf("  %s (exit=%d)\n", out, exit_code);
    } else {
        printf("  Data partition already mounted: %s", out);
    }

    // Create game directory
    snprintf(cmd, sizeof(cmd), "mkdir -p %s/%s", games_path, clv_code);
    cs_exec(cmd, out, sizeof(out), &exit_code);
    printf("  Created %s/%s (exit=%d)\n", games_path, clv_code, exit_code);

    /* ── Step 6: Upload ROM via Clovershell ── */
    printf("\n--- Uploading ROM (%zu bytes) ---\n", rom_size);

    // Write ROM via shell redirect (simple approach for single file)
    snprintf(cmd, sizeof(cmd),
        "cat > %s/%s/%s.sfc",
        games_path, clv_code, clv_code);

    // Start the cat command
    uint8_t buf[65536];
    int actual;

    // Kill existing, drain, ping
    cs_send(CMD_EXEC_KILL_ALL, 0, NULL, 0);
    usleep(50000);
    while (usb_read(buf, sizeof(buf), &actual, 100) == 0 && actual > 0);
    cs_send(CMD_PING, 0, NULL, 0);
    usb_read(buf, sizeof(buf), &actual, 2000);

    uint8_t session = 0;
    cs_send(CMD_EXEC_NEW_REQ, session, cmd, strlen(cmd));

    // Wait for EXEC_NEW_RESP and PID
    usleep(200000);
    while (usb_read(buf, sizeof(buf), &actual, 200) == 0 && actual > 0) {
        // Drain responses
    }

    // Send ROM data via stdin in chunks
    size_t offset = 0;
    size_t chunk_size = 8192; // Match Clovershell stdin chunk size
    while (offset < rom_size) {
        size_t remaining = rom_size - offset;
        size_t this_chunk = remaining < chunk_size ? remaining : chunk_size;

        rc = cs_exec_stdin(session, rom_data + offset, this_chunk);
        if (rc != 0) {
            printf("  Upload failed at offset %zu: rc=%d\n", offset, rc);
            break;
        }
        offset += this_chunk;

        // Small delay for flow control
        if (offset % (chunk_size * 4) == 0) {
            usleep(10000);
            // Drain any responses
            while (usb_read(buf, sizeof(buf), &actual, 10) == 0 && actual > 0);
        }

        printf("\r  Uploaded: %zu / %zu bytes (%d%%)",
               offset, rom_size, (int)(offset * 100 / rom_size));
    }
    printf("\n");

    // Close stdin (send empty stdin to signal EOF, then wait for result)
    usleep(200000);

    // Kill the session to close stdin
    cs_send(16, session, NULL, 0); // CMD_EXEC_KILL
    usleep(500000);

    // Drain
    while (usb_read(buf, sizeof(buf), &actual, 200) == 0 && actual > 0);

    /* ── Step 7: Write .desktop file ── */
    printf("\n--- Writing .desktop file ---\n");
    snprintf(cmd, sizeof(cmd),
        "cat > %s/%s/%s.desktop << 'DESKTOP_EOF'\n%sDESKTOP_EOF",
        games_path, clv_code, clv_code, desktop);
    cs_exec(cmd, out, sizeof(out), &exit_code);
    printf("  .desktop written (exit=%d)\n", exit_code);

    /* ── Step 8: Verify ── */
    printf("\n--- Verification ---\n");
    snprintf(cmd, sizeof(cmd), "ls -la %s/%s/", games_path, clv_code);
    cs_exec(cmd, out, sizeof(out), &exit_code);
    printf("%s\n", out);

    snprintf(cmd, sizeof(cmd), "wc -c < %s/%s/%s.sfc", games_path, clv_code, clv_code);
    cs_exec(cmd, out, sizeof(out), &exit_code);
    printf("  ROM size on console: %s", out);
    printf("  ROM size expected:   %zu\n", rom_size);

    // Compute CRC32 on console
    snprintf(cmd, sizeof(cmd), "crc32 %s/%s/%s.sfc 2>/dev/null || md5sum %s/%s/%s.sfc",
        games_path, clv_code, clv_code, games_path, clv_code, clv_code);
    cs_exec(cmd, out, sizeof(out), &exit_code);
    printf("  Console checksum: %s\n", out);

    printf("=== Sync test complete ===\n");

    libusb_release_interface(handle, 0);
    libusb_close(handle);
    libusb_exit(NULL);
    free(rom_data);
    return 0;
}
