# ChatGPT 半透明侧栏和顶栏

补丁为 Linux 主窗口启用透明表面，保留应用原有的半透明侧栏与顶栏 CSS。
KWin Better Blur DX 的 `WindowClasses` 由 `kde-config/kwinrc` 设置。

`chatgpt-desktop` 由 AUR 维护。`chatgpt-translucent-bars` 是独立补丁包，
其 pacman 钩子在 ChatGPT 或补丁包安装、更新后应用补丁，不保留旧 ASAR 备份。

```sh
paru --sudo run0 -S chatgpt-desktop chatgpt-translucent-bars
kde-config
```

完全退出并重新打开 ChatGPT 后生效。上游 bundle 结构变化时，钩子会报错并保留文件原状。
补丁会修改 ChatGPT 包内的 `app.asar`，因此 `pacman -Qkk chatgpt-desktop` 会报告此文件已修改。

若要取消补丁，先卸载 `chatgpt-translucent-bars`，再从 AUR 重新安装 `chatgpt-desktop`。
开发验证使用 `python chatgpt-translucent-bars/patch.py /path/to/staged/app.asar`。
