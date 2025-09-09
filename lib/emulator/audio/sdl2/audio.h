#ifndef AUDIO_H
#define AUDIO_H

#include <SDL.h>

// Function to check if audio device is active
int is_audio_device_active();

// Function to initialize SDL2 audio
int init_audio(int sample_rate, int channels, int buffer_size);

// Function to stream audio buffer with queue management
void stream_audio(const void *buffer, int length);

// Function to get queued audio size
Uint32 get_queued_audio_size();

// Function to clear queued audio
void clear_queued_audio();

// Function to terminate SDL2 audio
void terminate_audio();

// Function to get SDL error
const char *get_sdl_error();

#endif
