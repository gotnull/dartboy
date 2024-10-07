import 'dart:typed_data';

import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/mmu/mbc.dart';

/// Memory banking chip 1 (MBC1).
///
/// Supports two modes up to 16Mb ROM/8KB RAM or 4Mb ROM/32KB RAM
class MBC1 extends MBC {
  static const int ramDisableStart = 0x0000;
  static const int ramDisableEnd = 0x2000;

  static const int romBankSelectStart = 0x2000;
  static const int romBankSelectEnd = 0x4000;

  static const int selectMemoryModeStart = 0x6000;
  static const int selectMemoryModeEnd = 0x8000;

  /// MBC1 mode for 16Mb ROM and 8KB RAM, default mode of the controller.
  static const int mode16Rom8Ram = 0;

  /// MBC1 mode for 4Mb ROM and 32KB RAM
  static const int mode4Rom32Ram = 1;

  /// Indicates if the addresses 0x5000 to 0x6000 are redirected to RAM or to ROM
  int modeSelect = 0;

  /// Selected ROM bank
  int romBank = 0;

  MBC1(super.cpu);

  @override
  void reset() {
    super.reset();

    modeSelect = MBC1.mode16Rom8Ram;
    romBank = 1;

    cartRam = Uint8List(MBC.ramPageSize * 4);
    cartRam.fillRange(0, cartRam.length, 0);
  }

  /// Select the ROM bank to be used.
  void selectROMBank(int bank) {
    // Not usable banks, use the next bank available.
    if (bank == 0x00 || bank == 0x20 || bank == 0x40 || bank == 0x60) {
      bank++;
    }

    romBank = bank;
    romPageStart = Memory.romPageSize * bank;
  }

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    // Any value with 0xA in the lower 4 bits enables RAM, and any other value disables RAM.
    if (address >= MBC1.ramDisableStart && address < MBC1.ramDisableEnd) {
      if (cpu.cartridge.ramBanks > 0) {
        ramEnabled = (value & 0x0F) == 0x0A;
      }
    }
    // Writing to this address space selects the lower 5 bits of the ROM Bank Number.
    else if (address >= MBC1.romBankSelectStart &&
        address < MBC1.romBankSelectEnd) {
      selectROMBank((romBank & 0x60) | (value & 0x1F));
    }
    // Select a RAM Bank in range from 00-03h, or to specify the upper two bits (Bit 5-6) of the ROM Bank number, depending on the current ROM/RAM Mode.
    else if (address >= 0x4000 && address < 0x6000) {
      if (modeSelect == MBC1.mode16Rom8Ram) {
        ramPageStart = (value & 0x03) * MBC.ramPageSize;
      } else // if(modeSelect == MBC1.MODE_4ROM_32RAM)
      {
        selectROMBank((romBank & 0x1F) | ((value & 0x03) << 4));
      }
    }
    // Selects whether the two bits of the above register should be used as upper two bits of the ROM Bank, or as RAM Bank Number.
    else if (address >= MBC1.selectMemoryModeStart &&
        address < MBC1.selectMemoryModeEnd) {
      if (cpu.cartridge.ramBanks == 3) {
        modeSelect = (value & 0x01);
      }
    }
    // This area is used to address external RAM in the cartridge.
    else if (address >= MemoryAddresses.switchableRamStart &&
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
