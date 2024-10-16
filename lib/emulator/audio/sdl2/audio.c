#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include "audio.h"

// SDL audio device ID
SDL_AudioDeviceID audio_device;
SDL_AudioSpec audio_spec;

// Initialize audio with SDL
int init_audio(int sample_rate, int channels, int buffer_size)
{
  if (SDL_Init(SDL_INIT_AUDIO) < 0)
  {
    return -1;
  }

  SDL_zero(audio_spec);
  audio_spec.freq = sample_rate;
  audio_spec.format = AUDIO_S16LSB; // Signed 16-bit audio, little-endian
  audio_spec.channels = channels;
  audio_spec.samples = buffer_size;
  audio_spec.callback = NULL;

  audio_device = SDL_OpenAudioDevice(NULL, 0, &audio_spec, NULL, 0);
  if (audio_device == 0)
  {
    return -1;
  }

  SDL_PauseAudioDevice(audio_device, 0); // Start playing audio
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
