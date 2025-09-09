#ifndef AUDIO_H
#define AUDIO_H

#include <SDL.h>

int is_audio_device_active();

// Function to initialize SDL2 audio
int init_audio(int sample_rate, int channels, int buffer_size);

// Function to stream audio buffer
void stream_audio(const void *buffer, int length);

// Function to terminate SDL2 audio
void terminate_audio();

#endif
