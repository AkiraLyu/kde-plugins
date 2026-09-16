# KDE plugins and configuration

Personal Plasma 6 plugins, translucent themes, application patches and KDE settings.

| Directory | Component |
| --- | --- |
| `appgrid` | Plasma launcher and native QML modules |
| `adjustable-task-manager` | Task manager with configurable spacing and width |
| `kate-translucent-bars` | Kate translucent bars and session launcher |
| `wechat-glass-live` | KWin effect for XWayland WeChat and control command |
| `darkly-translucent` | Static Darkly 0.5.39 theme with 60% backgrounds |
| `chatgpt-translucent-bars` | ChatGPT window transparency patch and pacman hook |
| `kde-config` | Darkly/KWin settings, theme switcher and configuration command |

Arch packages are maintained in [AkiraLyu/pkgbuilds](https://github.com/AkiraLyu/pkgbuilds).
With that repository configured in Paru:

```sh
paru --sudo run0 -Sy --pkgbuilds
paru --sudo run0 -S kde-config chatgpt-translucent-bars
kde-config
```

`kde-config` installs App Grid, Adjustable Task Manager, Kate/WeChat plugins and the Plasma theme as dependencies.
`darkly-theme light|dark|toggle|apply|status` controls the appearance.
`wechat-glass-control status|enable|disable|opacity` controls the WeChat effect.
`chatgpt-desktop` comes from AUR. A separate `chatgpt-translucent-bars` package
reapplies the ASAR patch through a pacman post-transaction hook.
Restart applications after installing new native modules; log in again after a KWin ABI update.

Settings are installed under `/usr/share/kde-config` and applied to the current user by
`kde-config`. Personal desktop layouts, documents and session data are not packaged.
Component licenses and upstream attribution remain in their source files and metadata.
