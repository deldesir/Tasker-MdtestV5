#!/usr/bin/env bash

# Exit immediately if a command exits with a non-zero status, treat unset variables as errors, and trace commands
set -euo pipefail
set -x

# Get the directory where the script is located
CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Ensure the script runs on Termux
if [ -n "${TERMUX_VERSION:-}" ]; then
    echo "Updating package lists and installing necessary packages..."
    apt update
    yes | pkg install -y git golang ffmpeg termux-elf-cleaner p7zip 2>/dev/null | grep -E '(Need to get |Get:|Unpacking |Setting up )'
else
    echo "Error: This script should run on Termux."
    exit 1
fi

# Define directories
TMP_DIR="$(mktemp -d)"

# Navigate to temporary directory
cd "$TMP_DIR"

# Clone the original whatsmeow repository
echo "Cloning the original whatsmeow repository..."
git clone https://github.com/tulir/whatsmeow.git
cd whatsmeow

# Verify that mdtest does not exist
if [ -d "mdtest" ]; then
    echo "Note: mdtest directory already exists in the original repository."
else
    echo "mdtest directory does not exist in the original repository."
fi

# Fetch the mdtest directory from your forked repository's main branch
echo "Fetching mdtest directory from your forked repository's main branch..."
git remote add deldesir https://github.com/deldesir/whatsmeow.git
git fetch deldesir

# Check out the mdtest directory from a fork's main branch
git checkout deldesir/main -- mdtest || {
    echo "Error: Failed to fetch mdtest directory from your fork's main branch."
    exit 1
}

# Verify that mdtest/main.go exists
if [ ! -f "mdtest/main.go" ]; then
    echo "Error: mdtest/main.go not found after fetching from your fork."
    echo "Contents of mdtest directory:"
    ls -la mdtest
    exit 1
fi

# Debugging: List contents to confirm
echo "Listing whatsmeow directory after fetching mdtest:"
ls -la
echo "Listing mdtest directory:"
ls -la mdtest

# Clear the terminal for cleaner logs (optional)
clear 2>/dev/null || true

# Add extended support by executing scripts in the res directory
echo -e "\n------------------------\n\nAdding extended support:-\n"
find "$CURRENT_DIR/res" -maxdepth 1 -type f -name "*)*" -regex ".*/[0-9]+) .*" | sort -V | while read -r script; do
    echo "Executing script: $script"
    bash "$script" || {
        echo "Error: Failed to execute script $script"
        exit 1
    }
done
echo -e "\nDone adding extended support\n\n------------------------\n"

# Fix Termux permissions
echo "Fixing Termux permissions..."
value="true"
key="allow-external-apps"
file="/data/data/com.termux/files/home/.termux/termux.properties"
mkdir -p "$(dirname "$file")"
chmod 700 "$(dirname "$file")"

if ! grep -E "^${key}=.*" "$file" &>/dev/null; then
    if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
        newline=$'\n'
    else
        newline=""
    fi
    echo "${newline}${key}=${value}" >> "$file"
else
    sed -i'' -E "s/^${key}=.*/${key}=${value}/" "$file"
fi

# Navigate to mdtest directory
cd mdtest

# Tidy up Go modules
echo "Running 'go mod tidy'..."
go mod tidy

echo -e "\nFinal step: Building mdtest binary. This may take between 10 seconds to 1 minute...\n"

# Define the mdtest script
mdtest_script='#!/system/bin/sh

dir="$(cd "$(dirname "$0")"; pwd)"
bin_name="$(basename "$0")"
chmod 755 "$0" "$dir/${bin_name}.bin" 2>/dev/null >/dev/null

if [ "$(getprop ro.build.version.sdk)" -gt 28 ]; then
    if getprop ro.product.cpu.abilist | grep -q "64"; then
        exec /system/bin/linker64 "$dir/${bin_name}.bin" "$@"
    else
        exec /system/bin/linker "$dir/${bin_name}.bin" "$@"
    fi
else
    exec "$dir/${bin_name}.bin" "$@"
fi'

# Build the mdtest binary
echo "Building the mdtest binary with Go..."
go build -ldflags="-extldflags -s" -o mdtest.bin || {
    echo "Error: Go build failed."
    exit 1
}

# Clean the mdtest binary with termux-elf-cleaner
echo "Cleaning the mdtest binary with termux-elf-cleaner..."
termux-elf-cleaner "./mdtest.bin" &>/dev/null

# Navigate back to the original directory
cd "$CURRENT_DIR"

# Prepare the build directory
echo "Preparing the build directory..."
rm -rf build/mdtest.zip build/mdtest build/mdtest.bin &>/dev/null
mkdir -p build
cd build

# Copy the cleaned mdtest binary
echo "Copying the mdtest binary to the build directory..."
cp "$TMP_DIR/whatsmeow/mdtest/mdtest.bin" . || {
    echo "Error: Failed to copy mdtest.bin to the build directory."
    exit 1
}

# Create the mdtest script
echo "Creating the mdtest script..."
echo "$mdtest_script" > mdtest
chmod 755 mdtest mdtest.bin

# Package mdtest and its binary into a zip archive
echo "Packaging mdtest and mdtest.bin into mdtest.zip..."
7z a -tzip -mx=9 -bd -bso0 mdtest.zip mdtest mdtest.bin

# Clean up the individual files after packaging
rm -rf mdtest mdtest.bin &>/dev/null

# Clean up the temporary directory
rm -rf "$TMP_DIR" &>/dev/null

# Add media support using ffmpeg
echo -e "\nSuccessfully built mdtest. Adding media support using ffmpeg...\n"
cd "$CURRENT_DIR"
bash res/build_dynamic.sh ffmpeg

# Clean up package caches
pkg clean

# Set permissions for ffmpeg binaries
chmod 755 build/ffmpeg build/ffmpeg.bin

# Organize ffmpeg files
echo "Organizing ffmpeg binaries..."
rm -rf ffmpeg &>/dev/null
mkdir -p ffmpeg &>/dev/null
mv build/ffmpeg ffmpeg &>/dev/null
mv build/ffmpeg.bin ffmpeg &>/dev/null
mv build/lib-ffmpeg ffmpeg &>/dev/null
mv ffmpeg build &>/dev/null 

# Navigate to the build directory
cd build

# Add ffmpeg to mdtest.zip
echo -e "Adding ffmpeg to mdtest.zip...\n"
7z a -tzip -mx=9 -bd -bso0 mdtest.zip ffmpeg

# Clean up ffmpeg files after packaging
rm -rf ffmpeg &>/dev/null

# Extract mdtest.zip to the target directory
echo "Extracting mdtest.zip to ~/whatsmeow5/mdtest..."
mkdir -p ~/whatsmeow5/mdtest
7z x -aoa mdtest.zip -o"$HOME/whatsmeow5/mdtest" &>/dev/null

# Set execute permissions for the mdtest script
chmod 755 ~/whatsmeow5/mdtest/mdtest

echo -e "\nAll done! You can run Mdtest by executing the following commands:\n\n  cd ~/whatsmeow5/mdtest\n  ./mdtest\n\nType the commands without quotes to run Mdtest.\n"
