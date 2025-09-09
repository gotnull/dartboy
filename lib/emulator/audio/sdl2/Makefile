# Compiler and flags
CC = gcc
CFLAGS = -Wall -shared

# SDL2 config (fetching cflags and libs using sdl2-config)
SDL_CFLAGS = $(shell sdl2-config --cflags)
SDL_LIBS = $(shell sdl2-config --libs)

# Target shared library
TARGET = libaudio.dylib

# Source files
SRC = audio.c

# Destination directory for the dylibs
DEST_DIR = ../../../../macos/

# Build target
all: $(TARGET) copy_libs

# Rule to build the shared library
$(TARGET): $(SRC)
	$(CC) $(CFLAGS) $(SRC) $(SDL_CFLAGS) $(SDL_LIBS) -o $(TARGET)

# Rule to copy the necessary dylibs to the destination directory
copy_libs:
	cp libaudio.dylib libSDL2-2.0.0.dylib $(DEST_DIR)

# Clean the build
clean:
	rm -f $(TARGET)
