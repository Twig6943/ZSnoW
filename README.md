# ZSnoW
This is a basic XSnow clone written in zig for wayland. 
Since I swaped to sway I was missing the xsnow experience, so I created my own one.
I don't care about most features xsnow has, such as snow piling up or the santa and trees,
so they are not planned.


## Disclaimer
Since I'm new to zig and co, the code might contain alot of errors.
For now I can't see any huge memory leaks or issues, but when I find some
I will fix them, feel free to open an issue.


## Support
Your wayland compositor has to support the `zwlr_layer_shell_v1` protocoll.
To check if yours does refer to (here)[https://wayland.app/protocols/wlr-layer-shell-unstable-v1#compositor-support]

I am building against these protocoll versions:
| Protocol Name           | Version |
|-------------------------|---------|
| wl_compositor           | 6       |
| wl_shm                 | 2       |
| wl_output              | 4       |
| xdg_wm_base            | 1       |
| zwlr_layer_shell_v1    | 4       |

but I think some lower versions might be also supported try it out yourself and let me know :3

## Customization
You can easily add more/remove flake patterns or adjust scales in `src/flakes/flake.zig`.
