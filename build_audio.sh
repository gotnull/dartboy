#!/bin/bash

# Build script for Game Boy emulator audio library
set -e

echo "Building Game Boy APU audio library..."

# Create build directory if it doesn't exist
mkdir -p build_temp

# Compile the audio library
echo "Compiling audio.c..."
gcc -dynamiclib -O2 \
    -I/opt/homebrew/include/SDL2 \
    -L/opt/homebrew/lib \
    -lSDL2 \
    -o build_temp/libaudio.dylib \
    lib/emulator/audio/sdl2/audio.c

# Fix library paths for app bundle compatibility
echo "Fixing library paths..."

# Detect the actual SDL2 dylib path linked into libaudio and rewrite it to @rpath
SDL2_PATH=$(otool -L build_temp/libaudio.dylib | grep -o '/.*libSDL2.*\.dylib' | head -1)
if [ -n "$SDL2_PATH" ]; then
  install_name_tool -change "$SDL2_PATH" @rpath/libSDL2-2.0.0.dylib build_temp/libaudio.dylib
else
  echo "Warning: Could not detect SDL2 library path in libaudio.dylib"
fi

# Add rpath for loading libraries from same directory
install_name_tool -add_rpath @loader_path build_temp/libaudio.dylib

# Set library ID
install_name_tool -id @rpath/libaudio.dylib build_temp/libaudio.dylib

# Copy libraries to macos directory
echo "Copying libraries to macos directory..."
cp build_temp/libaudio.dylib macos/
cp /opt/homebrew/lib/libSDL2-2.0.0.dylib macos/
chmod u+w macos/libSDL2-2.0.0.dylib

# Fix SDL2 library ID
install_name_tool -id @rpath/libSDL2-2.0.0.dylib macos/libSDL2-2.0.0.dylib

# Clean up
rm -rf build_temp

echo "Audio library build complete!"
echo "Libraries are now located in the macos/ directory with proper rpath configuration."