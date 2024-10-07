import 'dart:math';
import 'dart:typed_data';
import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/mmu/mbc.dart';
import 'package:dartboy/emulator/memory/mmu/mbc1.dart';

class MBC3 extends MBC {
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
        ramEnabled = (value & 0x0F) == 0x0A;
      }

      rtcEnabled = (value & 0x0F) == 0x0A;
    }
    // Same as for MBC1, except that the whole 7 bits of the RAM Bank Number are written directly to this address.
    else if (address >= MBC1.romBankSelectStart &&
        address < MBC1.romBankSelectEnd) {
      romPageStart = Memory.romPageSize * max(value & 0x7F, 1);
    }
    // As for the MBC1s RAM Banking Mode, writing a value in range for 00h-03h maps the corresponding external RAM Bank (if any) into memory at A000-BFFF.
    // When writing a value of 08h-0Ch, this will map the corresponding RTC register into memory at A000-BFFF.
    // That register could then be read/written by accessing any address in that area, typically that is done by using address A000.
    else if (address >= 0x4000 && address < 0x6000) {
      // TODO <RTC WRITE>
      if (value >= 0x08 && value <= 0x0C) {
        if (rtcEnabled) {
          ramBank = -1;
        }
      } else if (value <= 0x03) {
        ramBank = value;
        ramPageStart = ramBank * MBC.ramPageSize;
      }
    }
    //Depending on the current Bank Number/RTC Register selection this memory space is used to access an 8KByte external RAM Bank, or a single RTC Register.
    else if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      if (ramEnabled && ramBank >= 0) {
        cartRam[address - MemoryAddresses.switchableRamStart + ramPageStart] =
            value;
      } else if (rtcEnabled) {
        // TODO <ADD CODE HERE TO WRITE RTC>
        // rtc[ramBank - 0x08] = value;
      }
    } else {
      super.writeByte(address, value);
    }
  }
}
