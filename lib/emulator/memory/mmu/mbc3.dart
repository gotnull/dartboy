import 'dart:math';
import 'dart:typed_data';
import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/mmu/mbc.dart';
import 'package:dartboy/emulator/memory/mmu/mbc1.dart';

class MBC3 extends MBC {
  static const int ramEnableValue = 0x0A;
  static const int rtcRegisterStart = 0x08;
  static const int rtcRegisterEnd = 0x0C;

  /// The currently selected RAM bank.
  int ramBank = 0;

  /// Whether the real time clock is enabled for IO.
  bool rtcEnabled = false;

  /// The real time clock registers.
  Uint8List rtc = Uint8List(4);

  MBC3(super.cpu);

  @override
  void reset() {
    super.reset();
    rtcEnabled = false;
    ramBank = 0;
    rtc.fillRange(0, rtc.length, 0);
    cartRam = Uint8List(MBC.ramPageSize * 4);
    cartRam.fillRange(0, cartRam.length, 0);
  }

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    if (address >= MBC1.ramDisableStart && address < MBC1.ramDisableEnd) {
      if (cpu.cartridge.ramBanks > 0) {
        ramEnabled = (value & 0x0F) == ramEnableValue;
      }
      rtcEnabled = (value & 0x0F) == ramEnableValue;
    } else if (address >= MBC1.romBankSelectStart &&
        address < MBC1.romBankSelectEnd) {
      romPageStart = Memory.romPageSize * max(value & 0x7F, 1);
    } else if (address >= 0x4000 && address < 0x6000) {
      // RTC register selection
      if (value >= rtcRegisterStart && value <= rtcRegisterEnd) {
        if (rtcEnabled) {
          ramBank = -1; // Select RTC register
        }
      } else if (value <= 0x03) {
        ramBank = value;
        // Mask RAM bank to wrap around based on actual RAM banks available
        int actualRamBank = ramBank;
        if (cpu.cartridge.ramBanks > 0) {
          actualRamBank = ramBank % cpu.cartridge.ramBanks;
        }
        ramPageStart = actualRamBank * MBC.ramPageSize;
      }
    } else if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      if (ramEnabled && ramBank >= 0) {
        cartRam[address - MemoryAddresses.switchableRamStart + ramPageStart] =
            value;
      } else if (rtcEnabled) {
        // Write to RTC register
        if (ramBank >= rtcRegisterStart && ramBank <= rtcRegisterEnd) {
          rtc[ramBank - rtcRegisterStart] = value;
        }
      }
    } else {
      super.writeByte(address, value);
    }
  }
}
