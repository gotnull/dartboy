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

  /// Select ROM bank to be used.
  void mapRom(int bank) {
    romBank = bank;
    // Ensure we don't go beyond the available ROM banks
    int maxBank = (cpu.cartridge.data.length ~/ Memory.romPageSize) - 1;
    int actualBank = bank.clamp(0, maxBank);
    romPageStart = Memory.romPageSize * actualBank;
  }

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    if (address >= MBC1.ramDisableStart && address < MBC1.ramDisableEnd) {
      if (cpu.cartridge.ramBanks > 0) {
        ramEnabled = (value & 0x0F) == 0x0A;
      }
    } else if (address >= 0x2000 && address < 0x3000) {
      // The lower 8 bits of the ROM bank number goes here. Writing 0 will indeed give bank 0 on MBC5, unlike other MBCs.
      int newBank = (romBank & 0x100) | (value & 0xFF);
      mapRom(newBank);
    } else if (address >= 0x3000 && address < 0x4000) {
      // The 9th bit of the ROM bank number goes here.
      int newBank = (romBank & 0xff) | ((value & 0x1) << 8);
      mapRom(newBank);
    } else if (address >= 0x4000 && address < 0x6000) {
      ramPageStart = (value & 0x0F) * MBC.ramPageSize;
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
