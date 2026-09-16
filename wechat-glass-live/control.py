#!/usr/bin/env python3
"""以当前用户身份查看或调整 WeChat Glass；安装和卸载交给 pacman。"""
import argparse
import json
import subprocess
import sys

EFFECT = "wechat-glass-live-v5"
GROUP = "Effect-wechat-glass-live"


def run(*command):
    result = subprocess.run(command, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(result.stderr.strip() or result.stdout.strip())
    return result.stdout.strip()


def effects(method, *arguments):
    return run("qdbus6", "org.kde.KWin", "/Effects", method, *arguments)


def write(group, key, value):
    run("kwriteconfig6", "--file", "kwinrc", "--group", group,
        "--key", key, str(value))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("status", "enable", "disable", "opacity"))
    parser.add_argument("value", nargs="?", type=float)
    args = parser.parse_args()
    if args.action == "opacity":
        if args.value is None or not 0.1 <= args.value <= 1.0:
            parser.error("opacity 需要 0.1 到 1.0 之间的数值。")
    elif args.value is not None:
        parser.error("只有 opacity 接受数值参数。")

    if args.action == "status":
        loaded = effects("isEffectLoaded", EFFECT) == "true"
        state = {"loaded": loaded}
        if loaded:
            state["renderer"] = json.loads(effects("debug", EFFECT, ""))
        print(json.dumps(state, ensure_ascii=False, indent=2))
        return

    if args.action == "enable":
        # 配置前确认二进制和模糊后端可用，避免写出无法生效的启用状态。
        if effects("isEffectSupported", EFFECT) != "true":
            raise RuntimeError("请用 paru --rebuild -S wechat-glass-live 重编译；KWin 更新后请重新登录。")
        if effects("isEffectLoaded", "better_blur_dx") != "true":
            raise RuntimeError("请先运行 kde-config，启用 Better Blur DX。")
        write(GROUP, "Enabled", "true")
        write("Plugins", EFFECT + "Enabled", "true")
    elif args.action == "disable":
        write(GROUP, "Enabled", "false")
        write("Plugins", EFFECT + "Enabled", "false")
    else:
        write(GROUP, "BackgroundOpacity", args.value)

    # KWin 先重读共享配置，再让已经加载的特效更新参数。
    run("qdbus6", "org.kde.KWin", "/KWin", "reconfigure")
    if args.action == "disable":
        effects("unloadEffect", EFFECT)
    else:
        if args.action == "enable" and effects("loadEffect", EFFECT) != "true":
            # loadEffect 对已加载的插件可能返回 false，再检查实际状态。
            if effects("isEffectLoaded", EFFECT) != "true":
                raise RuntimeError("KWin 未能加载插件，请检查用户会话日志。")
        if effects("isEffectLoaded", EFFECT) == "true":
            effects("reconfigureEffect", EFFECT)
            if args.action == "enable":
                state = json.loads(effects("debug", EFFECT, ""))
                if not state.get("shader_valid") or not state.get("enabled"):
                    raise RuntimeError("插件已加载，但着色器或启用状态异常。")
    print(f"已执行：{args.action}")


if __name__ == "__main__":
    try:
        main()
    except (OSError, RuntimeError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
