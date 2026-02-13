#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "audio.h"

// SDL audio device ID
static SDL_AudioDeviceID audio_device;

// SDL audio specification
static SDL_AudioSpec audio_spec;

// Audio buffer management
// At 44100 Hz stereo 16-bit = 176400 bytes/sec.
// Allow ~0.5s of audio queued before dropping to prevent latency buildup.
static const int MAX_QUEUED_AUDIO = 88200;

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

// Stream audio data to SDL with buffer management
void stream_audio(const void *buffer, int length)
{
  // Check if we have too much audio queued to prevent excessive latency
  Uint32 queued_bytes = SDL_GetQueuedAudioSize(audio_device);

  // If queue is too full, drop this sample rather than clearing the entire
  // queue (which causes audible pops). The queue will drain naturally.
  if (queued_bytes > MAX_QUEUED_AUDIO)
  {
    return;
  }

  // Queue the new audio data
  SDL_QueueAudio(audio_device, buffer, length);
}

// Terminate audio and clean up SDL
void terminate_audio(void)
{
  SDL_CloseAudioDevice(audio_device);
  SDL_Quit();
}

// Get queued audio size
Uint32 get_queued_audio_size()
{
  return SDL_GetQueuedAudioSize(audio_device);
}

// Clear queued audio
void clear_queued_audio()
{
  SDL_ClearQueuedAudio(audio_device);
}

// Get the last SDL error message
const char *get_sdl_error(void)
{
  return SDL_GetError();
}