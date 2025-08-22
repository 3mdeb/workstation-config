#!/bin/bash
#sleep 1
state=$(awk 'NF>1{print $NF}' /proc/acpi/button/lid/LID/state)
n=$(swaymsg -t get_outputs -p | grep -c "Output")

if [[ $state = "closed" && $n -gt "1" ]]
then
    swaymsg output eDP-1 disable
else
    swaymsg output eDP-1 enable
fi
