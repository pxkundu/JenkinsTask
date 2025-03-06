#!/bin/bash

# Define the output file
OUTPUT_FILE="time_log.txt"

# Ensure the file exists (create it if it doesn't)
touch "$OUTPUT_FILE"

# Get the current time in a readable format
CURRENT_TIME=$(date +"%Y-%m-%d %H:%M:%S")

# Append the current time to the file
echo "Time logged: $CURRENT_TIME" >> "$OUTPUT_FILE"

# Optional: Print confirmation to the terminal
echo "Current time ($CURRENT_TIME) written to $OUTPUT_FILE"
