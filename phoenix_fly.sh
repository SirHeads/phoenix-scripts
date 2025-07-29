#!/bin/bash
# phoenix_fly.sh
# Displays the Phoenix flying animation, optionally with a final message.
# Version: 1.0.1 (Added final message support)
# Author: (Incorporated logic from original common.sh and phoenix_fly.txt)

# Clear screen and set up
clear
trap "clear; tput cnorm; exit" 2 15
# Hide cursor
tput civis

# Function to draw the combined phoenix and text at specified row and column
draw_combined() {
    local row=$1
    local col=$2
    local visible_chars=$3
    clear
    # Print empty rows above the combined image
    for i in $(seq 1 $((row-1))); do
        echo
    done
    # Create the full string in the correct order
    full_string="^=||=8>     The Phoenix is Rising!"
    # Print only the visible portion of the string
    if [ $visible_chars -gt 0 ]; then
        visible_string="${full_string:0:$visible_chars}"
        printf "%*s\n" $col "$visible_string"
    fi
}

# Start position
row=1
col=1

# Fly string onto screen one character at a time (.15 seconds per character)
full_string="^=||=8>     The Phoenix is Rising!"
string_length=${#full_string}
for i in $(seq 1 $string_length); do
    draw_combined $row $col $i
    sleep 0.15
done

# Move the full string diagonally (1 vertical move every 12 characters)
# Reduced horizontal movement to 75% (90 characters instead of 120)
char_count=0
for i in $(seq 1 90); do  # Move 90 characters to the right (.75 of 120)
    col=$((col + 1))
    char_count=$((char_count + 1))
    # Move down one row every 12 characters
    if [ $((char_count % 12)) -eq 0 ]; then
        row=$((row + 1))
    fi
    draw_combined $row $col $string_length
    sleep 0.10
done

# Fly string off screen one character at a time (from left)
for i in $(seq $string_length -1 1); do
    draw_combined $row $col $i
    sleep 0.15
done

# --- NEW: Display Final Message ---
# Clean up cursor first
tput cnorm
clear

# Check if a message was passed as arguments
if [[ $# -gt 0 ]]; then
    # Join all arguments into a single message string
    final_message="$*"
    # Center the message
    term_width=$(tput cols)
    msg_width=${#final_message}
    padding=$(( (term_width - msg_width) / 2 ))
    # Display the message
    printf "%*s%s\n" $padding "" "$final_message"
fi
# --- END NEW ---

# Ensure cursor is visible at the end
tput cnorm
# Clear any residual state
clear
