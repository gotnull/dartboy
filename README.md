# DartBoy

A high-performance GameBoy and GameBoy Color emulator built with Flutter and Dart.

![Screenshot 2024-10-15 at 4 45 35 pm](https://github.com/user-attachments/assets/d512eb2a-b78e-4ab9-aaa5-dd26747c0ec0)
![Screenshot 2024-10-15 at 4 46 56 pm](https://github.com/user-attachments/assets/15772943-c4ce-4ce0-85f2-5ef38b3b6774)
![Screenshot 2024-10-15 at 4 47 53 pm](https://github.com/user-attachments/assets/e787f733-f498-41f6-910a-8939b78f117b)

## Features

- **Complete CPU Emulation**: Full Sharp LR35902 instruction set implementation
- **Memory Bank Controllers**: MBC1, MBC2, MBC3, MBC5 support
- **GameBoy Color**: Full color game compatibility
- **Audio**: Complete APU emulation with recent improvements
- **Cross-Platform**: Desktop, mobile, and web support

## Quick Start

```bash
git clone https://github.com/yourusername/dartboy.git
cd dartboy
flutter pub get
flutter run
```

## Controls

| Input | Desktop | Mobile |
|-------|---------|--------|
| D-Pad | Arrow Keys | Touch |
| A Button | Z | Touch |
| B Button | X | Touch |
| Start | Enter | Touch |
| Select | C | Touch |

## Test Results

Blargg's hardware test suite results:

| Test | Status |
|------|--------|
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

## Build Commands

```bash
# Desktop
flutter build windows
flutter build macos
flutter build linux

# Mobile
flutter build apk
flutter build ios

# Web
flutter build web
```

## Status

- ✅ CPU instruction set
- ✅ MBC1/MBC2/MBC3/MBC5
- ✅ Audio emulation
- ✅ GameBoy Color support
- ❌ Battery saves
- ❌ Timing accuracy
- ❌ Advanced test ROMs

## License

MIT License - see [LICENSE](LICENSE) for details.