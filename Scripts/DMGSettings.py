# dmgbuild writes Finder metadata directly, including on a headless release runner.
files = [defines["app"]]
symlinks = {"Applications": "/Applications"}
background = defines["background"]
format = "UDZO"
filesystem = "HFS+"
window_rect = ((200, 200), (640, 420))
default_view = "icon-view"
show_toolbar = False
show_sidebar = False
show_status_bar = False
show_pathbar = False
show_tab_view = False
arrange_by = None
grid_spacing = 64
icon_size = 112
text_size = 13
label_pos = "bottom"
icon_locations = {
    "Ckit.app": (174, 258),
    "Applications": (466, 258),
    # Keep artwork out of the layout even when Finder's Show Hidden Files is on.
    ".background.tiff": (174, 1024),
}
hide_extensions = ["Ckit.app"]
