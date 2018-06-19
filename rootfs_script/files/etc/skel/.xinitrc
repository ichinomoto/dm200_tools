xmodmap "~/.Xmodmap"

export LANG=ja_JP.UTF-8
export GTK_IM_MODULE=ibus
export XMODIFIERS=@im=ibus
export QT_IM_MODULE=ibus
ibus-daemon -drx&

xfce4-power-manager&

startxfce4
