#!/bin/bash
# hakchi-dump-full.sh — Complete kernel dump: FEL boot → Clovershell → NAND dump
set -euo pipefail
cd "$(dirname "$0")/.."

FEL_BOOT="./Tools/fel-boot"
CLOVER_EXEC="./Tools/clover-exec"
FES1="Resources/boot/fes1.bin"
UBOOT="Resources/boot/uboot.bin"
BOOTIMG="Resources/boot/boot.img"
BACKUP_DIR="$HOME/.hakchi2/kernel_backup"

echo "╔══════════════════════════════════════════════╗"
echo "║  hakchi kernel dump — Full FEL+Clovershell    ║"
echo "╚══════════════════════════════════════════════╝"
echo

# Check prerequisites
for f in "$FEL_BOOT" "$CLOVER_EXEC" "$FES1" "$UBOOT" "$BOOTIMG"; do
    [ -f "$f" ] || { echo "ERROR: Missing $f"; exit 1; }
done

# ── Phase 1: FEL memboot ─────────────────────────────────
echo "=== Phase 1: FEL Memboot ==="
echo
$FEL_BOOT "$FES1" "$UBOOT" "$BOOTIMG"
# fel-boot handles: FES1→DRAM→boot.img→U-Boot→execute
# At this point, kernel is booting from RAM

echo
echo "=== Phase 2: Wait for Clovershell ==="
echo "Waiting 20s for kernel boot + Clovershell daemon..."
sleep 20

# ── Phase 2: Clovershell kernel dump ─────────────────────
echo
echo "=== Phase 3: Kernel Dump via Clovershell ==="
echo

echo "[1/4] Checking Clovershell connection..."
# Use sudo for macOS USB access
RESULT=$(sudo "$CLOVER_EXEC" "echo OK" 2>/dev/null)
if [ "$RESULT" = "OK" ]; then
    echo "  Connected ✓"
else
    echo "  Connection test result: '$RESULT'"
    echo "  Retrying in 10s..."
    sleep 10
    RESULT=$(sudo "$CLOVER_EXEC" "echo OK" 2>/dev/null)
    [ "$RESULT" = "OK" ] || { echo "ERROR: Cannot connect via Clovershell"; exit 1; }
fi

echo "[2/4] Reading MTD partitions..."
sudo "$CLOVER_EXEC" "cat /proc/mtd" 2>/dev/null

echo "[3/4] Dumping kernel from NAND..."
KERNEL_MTD=$(sudo "$CLOVER_EXEC" "grep '\"kernel\"' /proc/mtd | cut -d: -f1" 2>/dev/null)
KERNEL_MTD="${KERNEL_MTD:-mtd2}"
KERNEL_MTD=$(echo "$KERNEL_MTD" | tr -d '[:space:]')
echo "  Partition: /dev/$KERNEL_MTD"

mkdir -p "$BACKUP_DIR"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOCAL_FILE="$BACKUP_DIR/kernel_backup_${TIMESTAMP}.img"

echo "  Reading /dev/$KERNEL_MTD..."
sudo "$CLOVER_EXEC" "dd if=/dev/$KERNEL_MTD bs=64k" -o "$LOCAL_FILE" 2>/dev/null

echo "[4/4] Verifying..."
FILE_SIZE=$(wc -c < "$LOCAL_FILE" | tr -d '[:space:]')
MD5=$(md5 -q "$LOCAL_FILE" 2>/dev/null || md5sum "$LOCAL_FILE" | cut -d' ' -f1)

echo
echo "╔══════════════════════════════════════════════╗"
echo "║  KERNEL DUMP COMPLETE ✓                       ║"
echo "╠══════════════════════════════════════════════╣"
echo "║  File: kernel_backup_${TIMESTAMP}.img"
echo "║  Size: $FILE_SIZE bytes"
echo "║  MD5:  $MD5"
echo "║  Path: $LOCAL_FILE"
echo "╚══════════════════════════════════════════════╝"
