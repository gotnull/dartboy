# DartBoy

A cross-platform GameBoy and GameBoy Color emulator built with [Flutter](https://flutter.dev/) and Dart. Runs seamlessly on desktop, mobile, and web platforms.

## Features

- **Complete CPU Support**: Full implementation of the Sharp [LR35902](https://www.pastraiser.com/cpu/gameboy/gameboy_opcodes.html) CPU instruction set
- **Memory Bank Controllers**: Support for MBC1, MBC3, MBC5, and basic ROM-only cartridges
- **GameBoy Color**: Basic support for [GameBoy Color](https://en.wikipedia.org/wiki/Game_Boy_Color) games
- **Audio System**: Comprehensive audio emulation with recent improvements
- **Cross-Platform**: Runs on Windows, macOS, Linux, Android, iOS, and web browsers

## Roadmap

- [✅] MBC1 memory bank controller support
- [✅] MBC2 memory bank controller support (basic implementation)
- [✅] MBC3 memory bank controller support
- [✅] MBC5 memory bank controller support
- [❌] Battery-backed save file support (.sav files)
- [✅] Audio emulation (recently improved)
- [❌] Timing accuracy improvements

![Screenshot 2024-10-15 at 4 45 35 pm](https://github.com/user-attachments/assets/d512eb2a-b78e-4ab9-aaa5-dd26747c0ec0)
![Screenshot 2024-10-15 at 4 46 56 pm](https://github.com/user-attachments/assets/15772943-c4ce-4ce0-85f2-5ef38b3b6774)
![Screenshot 2024-10-15 at 4 47 53 pm](https://github.com/user-attachments/assets/e787f733-f498-41f6-910a-8939b78f117b)

# [Blargg's test](https://github.com/retrio/gb-test-roms)

Blargg's Gameboy hardware test ROMs. Originally hosted at http://blargg.parodius.com/gb-tests/
before parodious.com went down. New official location: http://blargg.8bitalley.com/parodius/gb-tests/

| Test | Status |
|----------|----------|
| 01-special.gb | ✅ |
| 02-interrupts.gb | ✅ |
| 03-op sp,hl.gb | ✅ |
| 04-op r,imm.gb | ✅ |
| 05-op rp.gb | ✅ |
| 06-ld r,r.gb | ✅ |
| 07-jr,jp,call,ret,rst.gb | ✅ |
| 08-misc instrs.gb | ✅ |
| 09-op r,r.gb | ✅ |
| 10-bit ops.gb | ✅ |
| 11-op a,(hl).gb | ✅ |
| instr_timing | ❌ |
| interrupt_time | ❌ |
| mem_timing | ❌ |
| mem_timing-2 | ❌ |
| oam_bug | ❌ |
| halt_bug.gb | ❌ |
| cgb_sound | ❌ |

## Getting Started

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable version recommended)
- [Dart SDK](https://dart.dev/get-dart) (included with Flutter)

### Installation

1. Clone the repository:
   ```bash
   git clone https://github.com/yourusername/dartboy.git
   cd dartboy
   ```

2. Install dependencies:
   ```bash
   flutter pub get
   ```

3. Run the emulator:
   ```bash
   flutter run
   ```

### Controls

- **Desktop**: Arrow keys for D-pad, Z/X for A/B buttons, Enter for Start, C for Select
- **Mobile**: Use the on-screen touch controls

### Platform-Specific Builds

#### Web
```bash
flutter build web
flutter run -d chrome
```

#### Desktop
```bash
# Windows
flutter build windows

# macOS
flutter build macos

# Linux
flutter build linux
```

#### Mobile
```bash
# Android
flutter build apk

# iOS (macOS only)
flutter build ios
```

## Resources

### GameBoy Development
- [Pan Docs](https://gbdev.io/pandocs/) - Comprehensive GameBoy technical documentation
- [GameBoy CPU (LR35902) Opcodes](http://www.pastraiser.com/cpu/gameboy/gameboy_opcodes.html)
- [GameBoy Development Community](https://gbdev.gg8.se/)
- [Test ROMs](https://github.com/retrio/gb-test-roms) - Blargg's hardware test suite

### Flutter Development
- [Flutter Documentation](https://flutter.dev/docs)
- [Dart Language Tour](https://dart.dev/guides/language/language-tour)

### Educational Content
- [The Ultimate Game Boy Talk (33c3)](https://www.youtube.com/watch?v=HyzD8pNlpwI) - Excellent technical overview

## License

This project is licensed under the [MIT License](https://opensource.org/licenses/MIT) - see the [LICENSE](LICENSE) file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## Acknowledgments

- Built as a learning project to understand GameBoy hardware and emulation
- Thanks to the GameBoy development community for excellent documentation
- Special thanks to Blargg for the comprehensive test ROM suite
