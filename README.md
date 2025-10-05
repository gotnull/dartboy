# DartBoy

A high-performance GameBoy and GameBoy Color emulator built with Flutter and Dart.

<img width="1096" height="1007" alt="image" src="https://github.com/user-attachments/assets/2961d4a4-dcf8-4cea-9c82-3b683f887aeb" />
<img width="1096" height="1007" alt="image" src="https://github.com/user-attachments/assets/0abe6ead-89bf-471b-9032-6e91c6acde19" />
<img width="1096" height="1007" alt="image" src="https://github.com/user-attachments/assets/bb096543-fd83-4c18-b230-1974bd90bbeb" />
<img width="1096" height="1007" alt="image" src="https://github.com/user-attachments/assets/3a40c3fe-7b4c-4bcf-810f-8d47d523a9d4" />

## Features

- **Complete CPU Emulation**: Full Sharp LR35902 instruction set implementation
- **Memory Bank Controllers**: MBC1, MBC2, MBC3, MBC5 support
- **GameBoy Color**: Full color game compatibility
- **Audio**: Complete APU emulation with recent improvements
- **Cross-Platform**: Desktop, mobile, and web support

## Quick Start

```bash
git clone https://github.com/gotnull/dartboy.git
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

### Blargg's Test Suite

**CPU Instructions** (cpu_instrs) - All Passing ✅
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

**Other Tests**
| Test | Status |
|------|--------|
| instr_timing | ✅ |
| interrupt_time | ✅ |
| halt_bug | ✅ |
| mem_timing | ❌ |
| mem_timing-2 | ❌ |
| oam_bug | ⚠️ Partial |

**Audio Tests**
| Test | Status | Notes |
|------|--------|-------|
| cgb_sound | ⚠️ Partial | Tests 2, 6, 7 pass; Tests 1, 3, 4, 5 fail |
| dmg_sound | ❌ | Not yet passing |

### MagenTests - All Passing ✅

Complete suite passing including:
- Background & Window rendering
- Sprite rendering and priorities
- OAM and VRAM access
- Color palette handling
- DMA transfers
- Timer and interrupt timing
- Memory bank controllers

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

### Emulation Accuracy
- ✅ CPU instruction set (100% Blargg cpu_instrs)
- ✅ Interrupt timing (interrupt_time, halt_bug)
- ✅ Instruction timing (instr_timing)
- ✅ PPU/Graphics (All MagenTests passing)
- ✅ Memory Bank Controllers (MBC1/MBC2/MBC3/MBC5)
- ✅ GameBoy Color support
- ✅ Audio emulation (Partial - frame sequencer, length counters, basic channels working)
- ❌ Memory timing edge cases
- ❌ OAM bug reproduction
- ❌ Battery saves persistence

### Recent Audio Improvements
- Frame sequencer synchronized with DIV register
- Length counter obscure behavior implemented
- Sweep unit with overflow checking
- Volume envelope support
- Proper DAC enable/disable behavior
- CGB-specific timing adjustments

## License

MIT License - see [LICENSE](LICENSE) for details.
