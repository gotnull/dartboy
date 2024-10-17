#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "audio.h"

// SDL audio device ID
static SDL_AudioDeviceID audio_device;

// SDL audio specification
static SDL_AudioSpec audio_spec;

int is_audio_device_active()
{
  return SDL_GetAudioDeviceStatus(audio_device) == SDL_AUDIO_PLAYING;
}

// Initialize audio with SDL
int init_audio(int sample_rate, int channels, int buffer_size)
{
  // Initialize SDL audio subsystem
  if (SDL_Init(SDL_INIT_AUDIO) < 0)
  {
    return -1;
  }

  // Set up the audio specification
  SDL_zero(audio_spec);
  audio_spec.freq = sample_rate;
  audio_spec.format = AUDIO_S16LSB; // Signed 16-bit samples, in little-endian byte order
  audio_spec.channels = channels;
  audio_spec.samples = buffer_size;
  audio_spec.callback = NULL; // We'll use SDL_QueueAudio instead of a callback

  // Open the audio device
  audio_device = SDL_OpenAudioDevice(NULL, 0, &audio_spec, NULL, 0);
  if (audio_device == 0)
  {
    return -1;
  }

  // Start playing audio
  SDL_PauseAudioDevice(audio_device, 0);

  return 0;
}

// Stream audio data to SDL
void stream_audio(const void *buffer, int length)
{
  SDL_QueueAudio(audio_device, buffer, length);
}

// Terminate audio and clean up SDL
void terminate_audio(void)
{
  SDL_CloseAudioDevice(audio_device);
  SDL_Quit();
}

// Get the last SDL error message
const char *get_sdl_error(void)
{
  return SDL_GetError();
}