xmodmap "~/.Xmodmap"

export LANG=ja_JP.UTF-8
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx&

# Xfce starts the power manager and desktop applets through XDG autostart.
startxfce4
