#!/bin/bash

# OUTPUT_DIR="${XDG_PICTURES_DIR:-$HOME/Pictures}"
#
# if [[ ! -d "$OUTPUT_DIR" ]]; then
#   notify-send "Screenshot directory does not exist: $OUTPUT_DIR" -u critical -t 3000
#   exit 1
# fi

pkill slurp || hyprshot -m ${1:-region} --raw |
   satty --filename - \
       --early-exit \
       --copy-command 'wl-copy'

    # --filename - \
    # --output-filename "$OUTPUT_DIR/screenshot-$(date +'%Y-%m-%d_%H-%M-%S').png" \
    # --save-after-copy \
    # --actions-on-enter save-to-clipboard \
