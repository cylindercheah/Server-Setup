
# Desktop launcher setup
````md
This file creates **clickable desktop icons** for these GNOME apps on CentOS 9:

- **Firefox** — web browser
- **Terminal** — command line app
- **Settings** — system settings app

It copies each app’s `.desktop` launcher file into `~/Desktop/`, makes it executable, and marks it as trusted so the icon on the desktop can be clicked to open the app.
````
## Firefox

```bash
cp /usr/share/applications/firefox.desktop ~/Desktop/
chmod +x ~/Desktop/firefox.desktop
gio set ~/Desktop/firefox.desktop metadata::trusted true
````

## Terminal

```bash
cp /usr/share/applications/org.gnome.Terminal.desktop ~/Desktop/
chmod +x ~/Desktop/org.gnome.Terminal.desktop
gio set ~/Desktop/org.gnome.Terminal.desktop metadata::trusted true
```

## Settings

```bash
cp /usr/share/applications/gnome-control-center.desktop ~/Desktop/
chmod +x ~/Desktop/gnome-control-center.desktop
gio set ~/Desktop/gnome-control-center.desktop metadata::trusted true
```

## All together

```bash
cp /usr/share/applications/firefox.desktop ~/Desktop/
cp /usr/share/applications/org.gnome.Terminal.desktop ~/Desktop/
cp /usr/share/applications/gnome-control-center.desktop ~/Desktop/

chmod +x ~/Desktop/firefox.desktop
chmod +x ~/Desktop/org.gnome.Terminal.desktop
chmod +x ~/Desktop/gnome-control-center.desktop

gio set ~/Desktop/firefox.desktop metadata::trusted true
gio set ~/Desktop/org.gnome.Terminal.desktop metadata::trusted true
gio set ~/Desktop/gnome-control-center.desktop metadata::trusted true
```
