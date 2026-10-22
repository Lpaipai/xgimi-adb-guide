#!/system/bin/sh
# 2026/10/22 19:02:00 by liaoweipeng1
# NEW Z6X / v12.15.214 专用；默认只检查。不会 Root、刷机或删除应用。

BASE=/sdcard/xgimi-adb-guide
EXPECTED='Xgimi/ironman/ironman:8.0.0/OPR5.170623.014/v12.15.214:user/dev-keys'
MODE=${1:-check}

die() { printf 'STOP: %s\n' "$*"; exit 1; }
prop() { getprop "$1"; }
say() { printf '%s\n' "$*"; printf '%s\n' "$*" >> "$BASE/action.log"; }

case "$MODE" in
    check|enable|off|restore) ;;
    *) die 'Use: sh /sdcard/b.sh check|enable|off|restore' ;;
esac

printf 'XGIMI ADB Guide 1.0 | mode=%s\n' "$MODE"
printf 'Identity: '; id
printf 'Firmware: %s\n' "$(prop ro.build.fingerprint)"
printf 'ADB: daemon=%s persist=%s usb=%s port=%s\n' \
    "$(prop init.svc.adbd)" "$(prop persist.sys.usb.config)" \
    "$(prop sys.usb.config)" "$(prop service.adb.tcp.port)"

[ "$(prop ro.hardware)" = m7221 ] || die 'Unsupported hardware.'
[ "$(prop ro.build.version.sdk)" = 26 ] || die 'Expected SDK 26.'
[ "$(prop ro.product.model)" = 'XGIMI TV' ] || die 'Unexpected model.'
[ "$(prop ro.build.fingerprint)" = "$EXPECTED" ] || die 'Firmware not tested. Do not remove this check.'
[ "$(getenforce 2>/dev/null)" = Permissive ] || die 'Expected existing Permissive state. Do not change SELinux.'
[ -d /sys/class/android_usb ] || die 'USB framework missing.'
[ "$(prop init.svc.zygote)" = running ] || die 'Android runtime is not ready.'
[ "$MODE" != check ] || { printf 'CHECK PASS. No settings changed.\n'; exit 0; }

# 拒绝跟随链接。共享存储中的记录只作数据读取，绝不 source / eval。
[ ! -L "$BASE" ] || die 'State path is a symlink.'
umask 077
mkdir -p "$BASE" || die 'Cannot create state folder.'
[ ! -L "$BASE/action.log" ] || die 'Log path is a symlink.'
touch "$BASE/action.log" || die 'State folder not writable.'
OLD_PERSIST=$(prop persist.sys.usb.config)
OLD_USB=$(prop sys.usb.config)
OLD_PORT=$(prop service.adb.tcp.port)

rollback() {
    setprop service.adb.tcp.port "$OLD_PORT" >> "$BASE/action.log" 2>&1
    setprop persist.sys.usb.config "$OLD_PERSIST" >> "$BASE/action.log" 2>&1
    setprop sys.usb.config "$OLD_USB" >> "$BASE/action.log" 2>&1
    say "Rollback readback: persist=$(prop persist.sys.usb.config) usb=$(prop sys.usb.config) port=$(prop service.adb.tcp.port)"
}

set_checked() {
    setprop "$1" "$2" >> "$BASE/action.log" 2>&1
    if [ "$(prop "$1")" != "$2" ]; then
        rollback
        die "Property rejected: $1. Read action.log; do not repeat blindly."
    fi
}

if [ "$MODE" = off ]; then
    # 在投影仪本地终端执行；电脑的 ADB 会在这里断开。
    set_checked service.adb.tcp.port -1
    set_checked persist.sys.usb.config none
    set_checked sys.usb.config none
    sleep 2
    [ "$(prop init.svc.adbd)" = stopped ] || die 'Daemon not stopped. Verify from PC.'
    # 只有明确关闭成功才重新允许下一次用户主动 enable；不在失败路径自动重试。
    rm -f "$BASE/restart.once" || die 'ADB stopped, but could not reset the attempt marker.'
    say 'OFF: adbd stopped. Saved computer authorizations were not erased.'
    exit 0
fi

if [ "$MODE" = restore ]; then
    [ -f "$BASE/original/complete" ] || die 'No complete original-state backup.'
    [ "$(cat "$BASE/original/firmware")" = "$EXPECTED" ] || die 'Backup firmware mismatch.'
    P=$(cat "$BASE/original/persist")
    U=$(cat "$BASE/original/usb")
    T=$(cat "$BASE/original/port")
    case "$P$U" in *[!a-zA-Z0-9_,]*) die 'Invalid backup USB values.' ;; esac
    case "$T" in ''|-1|5555) ;; *) die 'Unexpected saved port; inspect manually.' ;; esac
    set_checked service.adb.tcp.port "$T"
    # 强制先停一次，确保 adbd 在需要重启时读取恢复后的端口。
    set_checked sys.usb.config none
    sleep 1
    set_checked persist.sys.usb.config "$P"
    set_checked sys.usb.config "$U"
    say 'RESTORED: three properties only. Framework was not restarted.'
    say 'This is not factory reset or authorization-key removal. Verify connectivity separately.'
    exit 0
fi

[ ! -e "$BASE/restart.once" ] || die 'Already attempted. Use PC to verify; do not delete marker to force retries.'
PID=$(pidof system_server 2>/dev/null)
[ -n "$PID" ] || die 'Cannot identify system_server.'

if [ ! -e "$BASE/original" ]; then
    mkdir "$BASE/original" || die 'Cannot save original state.'
    printf '%s\n' "$EXPECTED" > "$BASE/original/firmware" &&
    printf '%s\n' "$OLD_PERSIST" > "$BASE/original/persist" &&
    printf '%s\n' "$OLD_USB" > "$BASE/original/usb" &&
    printf '%s\n' "$OLD_PORT" > "$BASE/original/port" &&
    printf 'complete\n' > "$BASE/original/complete" || die 'Backup incomplete.'
fi
[ -f "$BASE/original/complete" ] || die 'Backup incomplete; inspect before continuing.'
say "Before: persist=$OLD_PERSIST usb=$OLD_USB port=$OLD_PORT pid=$PID"

set_checked service.adb.tcp.port 5555
set_checked persist.sys.usb.config adb
if [ "$OLD_PORT" != 5555 ]; then
    set_checked sys.usb.config none
    sleep 1
fi
set_checked sys.usb.config adb
sleep 2
[ "$(prop init.svc.adbd)" = running ] || { rollback; die 'ADB daemon failed to start.'; }
printf '%s\n' "$PID" > "$BASE/restart.once" || { rollback; die 'Cannot save one-attempt marker.'; }
say 'Restarting Android framework ONCE. Screen/network may disconnect briefly.'
say 'Wait for home screen, then check from PC. This output does NOT prove authorization.'
sync
setprop ctl.restart zygote >> "$BASE/action.log" 2>&1
RC=$?
[ "$RC" -eq 0 ] || { rollback; die 'Framework restart request rejected.'; }
sleep 12
NEW_PID=$(pidof system_server 2>/dev/null)
[ "$NEW_PID" != "$PID" ] || { rollback; die 'Framework did not restart. No second attempt.'; }
say "Restart requested: old=$PID new=$NEW_PID. PC verification is still required."
