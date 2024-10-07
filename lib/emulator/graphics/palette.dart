import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';

/// Palette is used to store the Gameboy palette colors.
///
/// Each palette is composed of four colors. For classic Gameboy, grayscale colors are stored.
/// For Gameboy Color, the palette stores RGB colors.
abstract class Palette {
  List<int> colors;

  Palette(this.colors);

  /// Gets the RGBA color associated with a given index.
  int getColor(int number);
}

class GBPalette implements Palette {
  final CPU cpu;
  final int register;

  @override
  List<int> colors;

  GBPalette(this.cpu, this.colors, this.register) {
    if (register != MemoryRegisters.bgp &&
        register != MemoryRegisters.obp0 &&
        register != MemoryRegisters.obp1) {
      throw Exception(
          "Register must be one of MemoryRegisters.BGP, MemoryRegisters.OBP0, or MemoryRegisters.OBP1.");
    }

    if (colors.length != 4) {
      throw Exception("Colors list must contain exactly 4 elements.");
    }
  }

  @override
  int getColor(int number) {
    return colors[(cpu.mmu.readRegisterByte(register) >> (number * 2)) & 0x3];
  }
}

class GBCPalette implements Palette {
  @override
  List<int> colors;

  GBCPalette(this.colors) {
    if (colors.length != 4) {
      throw Exception("Colors list must contain exactly 4 elements.");
    }
  }

  @override
  int getColor(int number) {
    return colors[number];
  }
}
