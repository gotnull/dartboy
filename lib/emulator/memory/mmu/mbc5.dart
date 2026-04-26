import 'dart:typed_data';

import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/mmu/mbc.dart';
import 'package:dartboy/emulator/memory/mmu/mbc1.dart';

class MBC5 extends MBC {
  MBC5(super.cpu);

  /// Indicates if the addresses 0x5000 to 0x6000 are redirected to RAM or to ROM
  int modeSelect = 0;

  /// Selected ROM bank
  int romBank = 0;

  @override
  void reset() {
    super.reset();

    modeSelect = 0;
    romBank = 0;

    cartRam = Uint8List(MBC.ramPageSize * 16);
    cartRam.fillRange(0, cartRam.length, 0);
    
    // Initialize ROM banking
    mapRom(romBank);
  }

  /// Select the ROM bank to be used in the switchable region.
  ///
  /// Unlike MBC1, MBC5 has no 0→1 substitution: bank 0 maps to ROM bank 0
  /// (i.e. the upper 16 KB mirrors the fixed bank when 0 is written).
  void mapRom(int bank) {
    romBank = bank;
    // Mask to the cartridge's actual bank count so out-of-range writes wrap
    // exactly as the chip's address pins do, instead of silently clamping.
    int numBanks = cpu.cartridge.romBanks;
    int actualBank = numBanks > 0 ? bank & (numBanks - 1) : bank;
    int totalBanks = cpu.cartridge.data.length ~/ Memory.romPageSize;
    if (totalBanks > 0 && actualBank >= totalBanks) {
      actualBank %= totalBanks;
    }
    romPageStart = Memory.romPageSize * actualBank;
  }

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    if (address >= MBC1.ramDisableStart && address < MBC1.ramDisableEnd) {
      // MBC5 RAM-enable is *strict*: only the exact value 0x0A enables RAM
      // (unlike MBC1/2/3, where any value with low nibble 0xA works). Some
      // games rely on this strictness — e.g. they write garbage like 0xBA
      // and expect RAM to remain disabled.
      ramEnabled = value == 0x0A;
    } else if (address >= 0x2000 && address < 0x3000) {
      // Lower 8 bits of ROM bank number. Writing 0 selects bank 0 (no quirk).
      int newBank = (romBank & 0x100) | (value & 0xFF);
      mapRom(newBank);
    } else if (address >= 0x3000 && address < 0x4000) {
      // Bit 8 of ROM bank number.
      int newBank = (romBank & 0xff) | ((value & 0x1) << 8);
      mapRom(newBank);
    } else if (address >= 0x4000 && address < 0x6000) {
      int ramBank = value & 0x0F;
      if (cpu.cartridge.ramBanks > 0) {
        ramBank = ramBank % cpu.cartridge.ramBanks;
      }
      ramPageStart = ramBank * MBC.ramPageSize;
    } else if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      if (ramEnabled) {
        cartRam[address - MemoryAddresses.switchableRamStart + ramPageStart] =
            value;
      }
    } else {
      super.writeByte(address, value);
    }
  }
}
