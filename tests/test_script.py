# 2026/10/22 19:05:00 by liaoweipeng1
"""隔离模拟 Android 属性服务；不连接设备。Python 3 + Bash，无第三方依赖。"""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / 'scripts/b.sh').read_text(encoding='utf-8')
BASH = os.environ.get('TEST_BASH') or shutil.which('bash')
if os.name == 'nt' and not os.environ.get('TEST_BASH'):
    BASH = r'C:\Program Files\Git\bin\bash.exe'
CASES = [
    'check', 'success', 'missing_usb', 'enforcing', 'wrong_sdk', 'wrong_firmware',
    'already_attempted', 'port_rejected', 'persist_rejected', 'daemon_failed',
    'restart_rejected', 'restart_ignored', 'pid_pending', 'off', 'restore',
    'missing_backup', 'invalid_backup', 'bad_mode',
]
MOCKS = r'''
getprop() { cat "$FIX/props/$1" 2>/dev/null; }
getenforce() { if [ "$CASE" = enforcing ]; then echo Enforcing; else echo Permissive; fi; }
pidof() { cat "$FIX/pid"; }
id() { echo 'uid=10040(test_app)'; }
sleep() { :; }
sync() { :; }
setprop() {
    printf '%s=%s\n' "$1" "$2" >> "$FIX/actions"
    case "$1" in
        service.adb.tcp.port)
            if [ "$CASE" = port_rejected ] && [ "$2" = 5555 ]; then return 1; fi ;;
        persist.sys.usb.config)
            if [ "$CASE" = persist_rejected ] && [ "$2" = adb ]; then return 1; fi ;;
        ctl.restart)
            [ "$2" = zygote ] || return 9
            [ "$CASE" != restart_rejected ] || return 1
            if [ "$CASE" = pid_pending ]; then
                : > "$FIX/pid"
            elif [ "$CASE" != restart_ignored ]; then
                echo 222 > "$FIX/pid"
            fi
            return 0 ;;
        sys.usb.config) ;;
        *) return 10 ;;
    esac
    printf '%s\n' "$2" > "$FIX/props/$1"
    case "$1" in
        persist.sys.usb.config|sys.usb.config)
            printf '%s\n' "$2" > "$FIX/props/sys.usb.config"
            if [ "$2" = adb ] && [ "$CASE" != daemon_failed ]; then
                echo running > "$FIX/props/init.svc.adbd"
            else
                echo stopped > "$FIX/props/init.svc.adbd"
            fi ;;
    esac
}
set -- "$MODE"
. "$FIX/run.sh"
'''


def main():
    subprocess.run([BASH, '-n', str(ROOT / 'scripts/b.sh')], check=True)
    results = []
    for case in CASES:
        with tempfile.TemporaryDirectory(prefix='mock-', dir=ROOT / 'tests') as name:
            fix = Path(name)
            (fix / 'props').mkdir()
            (fix / 'sdcard').mkdir()
            state = fix / 'sdcard/xgimi-adb-guide'
            if case != 'missing_usb':
                (fix / 'android_usb').mkdir()
            firmware = 'Xgimi/ironman/ironman:8.0.0/OPR5.170623.014/v12.15.214:user/dev-keys'
            values = {
                'ro.hardware': 'm7221', 'ro.build.version.sdk': '26',
                'ro.product.model': 'XGIMI TV', 'init.svc.zygote': 'running',
                'ro.build.fingerprint': firmware,
                'persist.sys.usb.config': 'none', 'sys.usb.config': 'none',
                'service.adb.tcp.port': '-1', 'init.svc.adbd': 'stopped',
            }
            if case == 'wrong_sdk':
                values['ro.build.version.sdk'] = '30'
            if case == 'wrong_firmware':
                values['ro.build.fingerprint'] = 'different/firmware'
            if case in ('off', 'restore', 'invalid_backup'):
                values.update({'persist.sys.usb.config': 'adb', 'sys.usb.config': 'adb',
                               'service.adb.tcp.port': '5555', 'init.svc.adbd': 'running'})
            for key, value in values.items():
                (fix / 'props' / key).write_text(value + '\n', encoding='utf-8')
            (fix / 'pid').write_text('111\n')
            if case in ('already_attempted', 'off'):
                state.mkdir()
                (state / 'restart.once').write_text('prior')
            if case in ('restore', 'invalid_backup'):
                backup = state / 'original'
                backup.mkdir(parents=True)
                for key, value in {'firmware': firmware, 'complete': 'yes', 'persist': 'none',
                                   'usb': 'none', 'port': '-1'}.items():
                    (backup / key).write_text(value + '\n')
                if case == 'invalid_backup':
                    (backup / 'persist').write_text('$(touch PWNED)')
            script = SOURCE.replace('/sdcard/', fix.as_posix() + '/sdcard/')
            script = script.replace('/sys/class/android_usb', fix.as_posix() + '/android_usb')
            (fix / 'run.sh').write_text(script, encoding='utf-8', newline='\n')
            mode = case if case in ('check', 'off', 'restore') else 'enable'
            if case in ('missing_backup', 'invalid_backup'):
                mode = 'restore'
            if case == 'bad_mode':
                mode = 'nonsense'
            wrapper = f"FIX='{fix.as_posix()}'\nCASE='{case}'\nMODE='{mode}'\n" + MOCKS
            result = subprocess.run([BASH, '--noprofile', '--norc', '-c', wrapper],
                                    capture_output=True, text=True, timeout=20)
            actions = (fix / 'actions').read_text().splitlines() if (fix / 'actions').exists() else []
            expected = 0 if case in ('check', 'success', 'pid_pending', 'off', 'restore') else 1
            assert result.returncode == expected, (case, result.stdout, result.stderr)
            assert actions.count('ctl.restart=zygote') <= 1, (case, actions)
            if case in ('check', 'missing_usb', 'enforcing', 'wrong_sdk', 'wrong_firmware',
                        'already_attempted', 'missing_backup', 'invalid_backup', 'bad_mode'):
                assert not actions, (case, actions)
            if case in ('port_rejected', 'persist_rejected', 'daemon_failed',
                        'restart_rejected', 'restart_ignored'):
                for key in ('service.adb.tcp.port', 'persist.sys.usb.config', 'sys.usb.config'):
                    assert (fix / 'props' / key).read_text().strip() == values[key], (case, key)
            if case in ('success', 'pid_pending'):
                assert actions.count('ctl.restart=zygote') == 1
                assert (state / 'original/complete').exists()
                assert (state / 'original/port').read_text().strip() == '-1'
            if case in ('off', 'restore'):
                assert (fix / 'props/init.svc.adbd').read_text().strip() == 'stopped'
                assert not any('ctl.restart' in a for a in actions)
                if case == 'off':
                    assert not (state / 'restart.once').exists()
            results.append({'case': case, 'passed': True})
    report = {'kind': 'isolated_simulation', 'device_test': False, 'cases': results}
    (ROOT / 'evidence/script-tests.json').write_text(json.dumps(report, indent=2) + '\n', encoding='utf-8')
    print(f'{len(results)} cases passed (simulation only).')


if __name__ == '__main__':
    main()
