import 'dart:typed_data';

import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/mmu/mbc.dart';

/// Memory Bank Controller 2 (MBC2).
///
/// Up to 256 KB ROM (16 banks) and a built-in 512 × 4-bit RAM. The single
/// register at $0000-$3FFF doubles as RAM-enable and ROM-bank-select; the
/// distinction is made by bit 8 of the address. The cartridge RAM is only
/// 4 bits wide — high nibble of reads is undefined (we return 0xFn) and
/// writes ignore the high nibble.
class MBC2 extends MBC {
  /// MBC2 has its own internal RAM: 512 nibbles = 256 bytes. We back it with
  /// 512 bytes so `readByte`/`writeByte` can index it like a normal Uint8List.
  static const int mbc2RamSize = 512;

  int romBank = 1;

  MBC2(super.cpu);

  @override
  void reset() {
    super.reset();
    romBank = 1;
    cartRam = Uint8List(mbc2RamSize);
    cartRam.fillRange(0, cartRam.length, 0);
  }

  @override
  int readByte(int address) {
    address &= 0xFFFF;

    if (address >= MemoryAddresses.cartridgeRomSwitchableStart &&
        address < MemoryAddresses.cartridgeRomEnd) {
      int offset = romBank * Memory.romPageSize +
          (address - MemoryAddresses.cartridgeRomSwitchableStart);
      final data = cpu.cartridge.data;
      if (offset >= data.length) offset %= data.length;
      return data[offset] & 0xFF;
    }

    if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      if (!ramEnabled) return 0xFF;
      // 512 nibbles wrap-mirrored across the whole $A000-$BFFF window.
      int idx = (address - MemoryAddresses.switchableRamStart) & 0x1FF;
      // Pan Docs: high nibble reads as 1s.
      return (cartRam[idx] & 0x0F) | 0xF0;
    }

    return super.readByte(address);
  }

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    // RAM enable / ROM bank select: $0000-$3FFF. Bit 8 of address picks which.
    if (address < MemoryAddresses.cartridgeRomSwitchableStart) {
      if ((address & 0x0100) == 0) {
        // Bit 8 = 0 → RAM enable register (any value with low nibble == 0xA).
        ramEnabled = (value & 0x0F) == 0x0A;
      } else {
        // Bit 8 = 1 → ROM bank select. Only the low 4 bits matter; writing 0
        // selects bank 1 instead.
        int bank = value & 0x0F;
        if (bank == 0) bank = 1;
        // Mask against actual ROM bank count (always power-of-two on real
        // cartridges) so a too-high value wraps rather than running off the
        // end of the cartridge data.
        int numBanks = cpu.cartridge.romBanks;
        if (numBanks > 0) bank &= numBanks - 1;
        if (bank == 0) bank = 1;
        romBank = bank;
      }
      return;
    }

    if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      if (!ramEnabled) return;
      int idx = (address - MemoryAddresses.switchableRamStart) & 0x1FF;
      cartRam[idx] = value & 0x0F;
      return;
    }

    super.writeByte(address, value);
  }
}
