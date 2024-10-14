import 'dart:math';
import 'dart:typed_data';

import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/memory/mmu/mbc1.dart';
import 'package:dartboy/emulator/memory/mmu/mbc2.dart';
import 'package:dartboy/emulator/memory/mmu/mbc3.dart';
import 'package:dartboy/emulator/memory/mmu/mbc5.dart';
import 'package:dartboy/emulator/memory/mmu/mmu.dart';

/// Stores the cartridge information and data.
///
/// Also manages the cartridge type and is responsible for the memory bank switching.
class Cartridge {
  /// Data stored in the cartridge (directly loaded from a ROM file).
  List<int> data = [];

  /// Size of the memory in bytes
  int size = 0;

  /// Cartridge name read from the
  String name = "";

  /// Cartridge type, there are 16 different types.
  ///
  /// Read from memory address 0x147 (Check page 11 of the GB CPU manual for details)
  int type = 0;

  /// In cartridge ROM configuration. Read from the address 0x148.
  ///
  /// (Check page 12 of the GB CPU manual for details)
  int romType = 0;

  /// Indicates how many rom banks there are available.
  ///
  /// Each ROM bank has 32KB in size
  int romBanks = 0;

  /// In cartridge RAM configuration. Read from the address 0x149.
  ///
  /// (Check page 12 of the GB CPU manual for details)
  int ramType = 0;

  /// Indicates how many RAM banks are available in the cartridge.
  ///
  /// Each bank has 8KBytes in size.
  int ramBanks = 0;

  /// Cartridge checksum, used to check if the data of the game is good, and also used to select the better color palette in classic gb games.
  int checksum = 0;

  /// In CGB cartridges the upper bit is used to enable CGB functions. This is required, otherwise the CGB switches itself into Non-CGB-Mode.
  ///
  /// There are two different CGB modes 80h Game supports CGB functions, but works on old gameboys also, C0h Game works on CGB only.
  GameboyType gameboyType = GameboyType.color;

  /// SGB mode indicates if the game has super gameboy features
  bool superGameboy = false;

  // 0x134 - 0x143 Title section in the header
  Uint8List title = Uint8List(0x144 - 0x134);

  // Manufacturer Code (0x13F - 0x142)
  Uint8List get cartManufacturerCode =>
      title.sublist(0x13F - 0x134, 0x143 - 0x134);

  // CGB Flag (0x143)
  int get cartCgbFlag => title[0x143 - 0x134];

  /// Load cartridge byte data
  void load(List<int> data) {
    size = (data.length / 1024).round();
    this.data = data;

    type = readByte(0x147);
    name = String.fromCharCodes(readBytes(0x134, 0x142));
    romType = readByte(0x148);
    ramType = readByte(0x149);
    gameboyType =
        readByte(0x143) == 0x80 ? GameboyType.color : GameboyType.classic;
    superGameboy = readByte(0x146) == 0x3;

    // Calculate the special value used by the CGB boot ROM to colorize some monochrome games.
    int chk = 0;
    for (int i = 0; i < 16; i++) {
      chk += data[0x134 + i];
    }
    checksum = chk & 0xFF;

    setBankSizeRAM();
    setBankSizeROM();
  }

  String getRamSize() {
    switch (ramType) {
      case 0:
        return "None";
      case 1:
        return "2k";
      case 2:
        return "8k";
      case 3:
        return "32k";
      case 4:
        return "128k";
      case 5:
        return "64k";
      default:
        return "Unknown";
    }
  }

  /// Create a the memory controller of the cartridge.
  MMU createController(CPU cpu) {
    if (type == CartridgeType.rom) {
      print('Created basic MMU unit.');
      return MMU(cpu);
    } else if (type == CartridgeType.mbc1 ||
        type == CartridgeType.mbc1Ram ||
        type == CartridgeType.mbc1RamBatt) {
      print('Created MBC1 unit.');
      return MBC1(cpu);
    } else if (type == CartridgeType.mbc2 || type == CartridgeType.mbc2Batt) {
      print('Created MBC2 unit.');
      return MBC2(cpu);
    } else if (type == CartridgeType.mbc3 ||
        type == CartridgeType.mbc3Ram ||
        type == CartridgeType.mbc3RamBatt ||
        type == CartridgeType.mbc3TimerBatt ||
        type == CartridgeType.mbc3TimerRamBatt) {
      print('Created MBC3 unit.');
      return MBC3(cpu);
    } else if (type == CartridgeType.mbc5 ||
        type == CartridgeType.mbc5Ram ||
        type == CartridgeType.mbc5RamBatt ||
        type == CartridgeType.mbc5Rumble ||
        type == CartridgeType.mbc5RumbleSram ||
        type == CartridgeType.mbc5RumbleSramBatt) {
      print('Created MBC5 unit.');
      return MBC5(cpu);
    }

    // If none of the cases match, throw an exception
    throw Exception('Unsupported cartridge type: $type');
  }

  /// Checks if the cartridge has a internal battery to keep the RAM state.
  bool hasBattery() {
    return type == CartridgeType.romRamBatt ||
        type == CartridgeType.romMmm01SramBatt ||
        type == CartridgeType.mbc1RamBatt ||
        type == CartridgeType.mbc3TimerBatt ||
        type == CartridgeType.mbc3TimerRamBatt ||
        type == CartridgeType.mbc3RamBatt ||
        type == CartridgeType.mbc5RamBatt ||
        type == CartridgeType.mbc5RumbleSramBatt;
  }

  /// Set how many ROM banks exist based on the ROM type.
  void setBankSizeROM() {
    if (romType == 52) {
      romBanks = 72;
    } else if (romType == 53) {
      romBanks = 80;
    } else if (romType == 54) {
      romBanks = 96;
    } else {
      romBanks = (pow(2, romType + 1)).toInt();
    }
  }

  /// Set how many RAM banks exist in the cartridge based on the RAM type.
  void setBankSizeRAM() {
    if (ramType == 0) {
      ramBanks = 0;
    } else if (ramType == 1) {
      ramBanks = 1;
    } else if (ramType == 2) {
      ramBanks = 1;
    } else if (ramType == 3) {
      ramBanks = 4;
    } else if (ramType == 4) {
      ramBanks = 16;
    }
  }

  /// Read a range of bytes from the cartridge.
  List<int> readBytes(int initialAddress, int finalAddress) {
    return data.sublist(initialAddress, finalAddress);
  }

  /// Read a single byte from cartridge
  int readByte(int address) {
    return data[address] & 0xFF;
  }
}

/// Enum to indicate the gameboy type present in the cartridge.
enum GameboyType {
  classic,
  color,
}

/// List of all cartridge types available in the game boy.
///
/// Cartridges have different memory configurations.
class CartridgeType {
  static const int rom = 0x00;
  static const int romRam = 0x08;
  static const int romRamBatt = 0x09;
  static const int romMmm01 = 0x0B;
  static const int romMmm01Sram = 0x0C;
  static const int romMmm01SramBatt = 0x0D;

  static const int mbc1 = 0x01;
  static const int mbc1Ram = 0x02;
  static const int mbc1RamBatt = 0x03;

  static const int mbc2 = 0x05;
  static const int mbc2Batt = 0x06;

  static const int mbc3TimerBatt = 0x0F;
  static const int mbc3TimerRamBatt = 0x10;
  static const int mbc3 = 0x11;
  static const int mbc3Ram = 0x12;
  static const int mbc3RamBatt = 0x13;

  static const int mbc5 = 0x19;
  static const int mbc5Ram = 0x1A;
  static const int mbc5RamBatt = 0x1B;
  static const int mbc5Rumble = 0x1C;
  static const int mbc5RumbleSram = 0x1D;
  static const int mbc5RumbleSramBatt = 0x1E;

  static const int pocketCam = 0x1F;
  static const int bandaiTama5 = 0xFD;
  static const int hudsonHuc3 = 0xFE;
  static const int hudsonHuc1 = 0xFF;
}
