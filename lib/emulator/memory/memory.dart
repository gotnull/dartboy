import 'dart:math';
import 'dart:typed_data';

import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';
import 'package:dartboy/emulator/memory/dma.dart';
import 'package:dartboy/emulator/memory/gamepad.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';

/// Generic memory container used to represent memory spaces in the gameboy system.
///
/// Contains all the memory spaces of the gameboy except for the cartridge data.
///
/// Can be used to represent booth ROM or RAM memory and provides Byte based access.
class Memory {
  /// Size of a page of Video RAM, in bytes. 8kb.
  static const int vramPageSize = 0x2000;

  /// Size of a page of Work RAM, in bytes. 4kb.
  static const int wramPageSize = 0x1000;

  /// Size of a page of ROM, in bytes. 16kb.
  static const int romPageSize = 0x4000;

  /// Register values contains mostly control flags, mapped from 0xFF00-0xFF7F + HRAM (0xFF80-0xFFFE) + Interrupt Enable Register (0xFFFF)
  late Uint8List registers;

  /// OAM (Object Attribute Memory) or (Sprite Attribute Table), mapped from 0xFE00-0xFE9F.
  late Uint8List oam;

  /// Video RAM, mapped from 0x8000-0x9FFF.
  /// On the GBC, this bank is switchable 0-1 by writing to 0xFF4F.
  late Uint8List vram;

  /// Work RAM, mapped from 0xC000-0xCFFF and 0xD000-0xDFFF.
  ///
  /// On the GBC, this bank is switchable 1-7 by writing to 0xFF07.
  late Uint8List wram;

  /// The current page of Video RAM, always multiples of vramPageSize.
  ///
  /// On non-GBC, this is always 0.
  int vramPageStart = 0;

  /// The current page of Work RAM, always multiples of wramPageSize.
  ///
  /// On non-GBC, this is always wramPageSize.
  int wramPageStart = 0;

  /// The current page of ROM, always multiples of romPageSize.
  int romPageStart = 0;

  /// CPU that is using the MMU, useful to trigger changes in other parts affected by memory changes.
  CPU cpu;

  /// DMA memory controller (only available on gameboy color games).
  ///
  /// Used for direct memory copy operations.
  DMA? dma;

  Memory(this.cpu);

  /// Initialize the memory, create the data array with the defined size.
  ///
  /// Reset the memory to default boot values, Also sets all bytes in the memory space to 0 value.
  ///
  /// Should be used to reset the system state after loading data.
  void reset() {
    vramPageStart = 0;
    wramPageStart = Memory.wramPageSize;
    romPageStart = Memory.romPageSize;

    registers = Uint8List(0x100);
    registers.fillRange(0, registers.length, 0);

    oam = Uint8List(0xA0);
    oam.fillRange(0, oam.length, 0);

    wram = Uint8List(Memory.wramPageSize *
        (cpu.cartridge.gameboyType == GameboyType.color ? 8 : 2));
    wram.fillRange(0, wram.length, 0);

    vram = Uint8List(Memory.vramPageSize *
        (cpu.cartridge.gameboyType == GameboyType.color ? 2 : 1));
    vram.fillRange(0, vram.length, 0);

    writeIO(0x04, 0xAB);
    writeIO(0x10, 0x80);
    writeIO(0x11, 0xBF);
    writeIO(0x12, 0xF3);
    writeIO(0x14, 0xBF);
    writeIO(0x16, 0x3F);
    writeIO(0x19, 0xBF);
    writeIO(0x1A, 0x7F);
    writeIO(0x1B, 0xFF);
    writeIO(0x1C, 0x9F);
    writeIO(0x1E, 0xBF);
    writeIO(0x20, 0xFF);
    writeIO(0x23, 0xBF);
    writeIO(0x24, 0x77);
    writeIO(0x25, 0xF3);
    writeIO(0x26, cpu.cartridge.superGameboy ? 0xF0 : 0xF1);
    writeIO(0x40, 0x91);
    writeIO(0x47, 0xFC);
    writeIO(0x48, 0xFF);
    writeIO(0x49, 0xFF);

    for (int i = 0; i < registers.length; i++) {
      if (registers[i] == 0) {
        writeIO(i, 0x0);
      }
    }
  }

  /// Write a byte into memory address.
  ///
  /// The memory is not directly accessed some addresses might be used for I/O or memory control operations.
  void writeByte(int address, int value) {
    address &= 0xFFFF;

    if (value > 0xFF) {
      throw Exception(
        'Tring to write ${value.toRadixString(16)} (>0xFF) into ${address.toRadixString(16)}.',
      );
    }

    // ROM
    if (address < MemoryAddresses.cartridgeRomEnd) {
      return;
    }
    // VRAM
    else if (address >= MemoryAddresses.videoRamStart &&
        address < MemoryAddresses.videoRamEnd) {
      vram[vramPageStart + address - MemoryAddresses.videoRamStart] = value;
    }
    // Cartridge RAM
    else if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      return;
    }
    // RAM A
    else if (address >= MemoryAddresses.ramAstart &&
        address < MemoryAddresses.ramASwitchableStart) {
      wram[address - MemoryAddresses.ramAstart] = value;
    } else if (address >= MemoryAddresses.ramASwitchableStart &&
        address < MemoryAddresses.ramAEnd) {
      wram[address - MemoryAddresses.ramASwitchableStart + wramPageStart] =
          value;
    }
    // RAM echo
    else if (address >= MemoryAddresses.ramAEchoStart &&
        address < MemoryAddresses.ramAEchoEnd) {
      writeByte(address - MemoryAddresses.ramAEchoStart, value);
    }
    // Empty
    else if (address >= MemoryAddresses.emptyAStart &&
        address < MemoryAddresses.emptyAEnd) {
      return;
    }
    // OAM
    else if (address >= MemoryAddresses.oamStart &&
        address < MemoryAddresses.emptyAEnd) {
      oam[address - MemoryAddresses.oamStart] = value;
    }
    // IO
    else if (address >= MemoryAddresses.ioStart) {
      writeIO(address - MemoryAddresses.ioStart, value);
    }
  }

  /// Read a byte from memory address
  ///
  /// If the address falls into the cartridge addressing zone read directly from the cartridge object.
  int readByte(int address) {
    address &= 0xFFFF;

    // ROM
    if (address < MemoryAddresses.cartridgeRomSwitchableStart) {
      return cpu.cartridge.data[address];
    }
    if (address >= MemoryAddresses.cartridgeRomSwitchableStart &&
        address < MemoryAddresses.cartridgeRomEnd) {
      return cpu.cartridge.data[
          romPageStart + address - MemoryAddresses.cartridgeRomSwitchableStart];
    }
    // VRAM
    else if (address >= MemoryAddresses.videoRamStart &&
        address < MemoryAddresses.videoRamEnd) {
      return vram[vramPageStart + address - MemoryAddresses.videoRamStart];
    }
    // Cartridge RAM
    else if (address >= MemoryAddresses.switchableRamStart &&
        address < MemoryAddresses.switchableRamEnd) {
      return 0x0;
    }
    // RAM A
    else if (address >= MemoryAddresses.ramAstart &&
        address < MemoryAddresses.ramASwitchableStart) {
      return wram[address - MemoryAddresses.ramAstart];
    } else if (address >= MemoryAddresses.ramASwitchableStart &&
        address < MemoryAddresses.ramAEnd) {
      return wram[
          wramPageStart + address - MemoryAddresses.ramASwitchableStart];
    }
    // RAM echo
    else if (address >= MemoryAddresses.ramAEchoStart &&
        address < MemoryAddresses.ramAEchoEnd) {
      return readByte(address - MemoryAddresses.ramAEchoStart);
    }
    // Empty A
    else if (address >= MemoryAddresses.emptyAStart &&
        address < MemoryAddresses.emptyAEnd) {
      return 0xFF;
    }
    // OAM
    else if (address >= MemoryAddresses.oamStart &&
        address < MemoryAddresses.emptyAEnd) {
      return oam[address - MemoryAddresses.oamStart];
    }
    // IO
    else if (address >= MemoryAddresses.ioStart) {
      return readIO(address - MemoryAddresses.ioStart);
    }

    throw Exception("Trying to access invalid address.");
  }

  /// Write data into the IO section of memory space.
  void writeIO(int address, int value) {
    if (value > 0xFF) {
      throw Exception(
        'Tring to write ${value.toRadixString(16)} (>0xFF) into ${address.toRadixString(16)}.',
      );
    }
    if (address > 0xFF) {
      throw Exception(
        'Tring to write register ${value.toRadixString(16)} into ${address.toRadixString(16)} (>0xFF).',
      );
    }

    if (address == MemoryRegisters.doubleSpeed) {
      cpu.setDoubleSpeed((value & 0x01) != 0);
    }
    // Background Palette Data
    else if (address == MemoryRegisters.backgroundPaletteData) {
      if (cpu.cartridge.gameboyType == GameboyType.color) {
        int index = registers[MemoryRegisters.backgroundPaletteIndex];
        int currentRegister = index & 0x3f;
        cpu.ppu.setBackgroundPalette(currentRegister, value);

        if ((index & 0x80) != 0) {
          currentRegister++;
          currentRegister %= 0x40;
          registers[MemoryRegisters.backgroundPaletteIndex] =
              (0x80 | currentRegister) & 0xFF;
        }
      }
    }
    // Sprite Palette Data
    else if (address == MemoryRegisters.spritePaletteData) {
      if (cpu.cartridge.gameboyType == GameboyType.color) {
        int index = registers[MemoryRegisters.spritePaletteIndex];
        int currentRegister = index & 0x3f;
        cpu.ppu.setSpritePalette(currentRegister, value);

        if ((index & 0x80) != 0) {
          currentRegister++;
          currentRegister %= 0x40;
          registers[MemoryRegisters.spritePaletteIndex] =
              (0x80 | currentRegister) & 0xFF;
        }
      }
    }
    // Start H-DMA transfer
    else if (address == MemoryRegisters.hdma) {
      if (cpu.cartridge.gameboyType != GameboyType.classic) {
        // print("Not possible to used H-DMA transfer on GB classic.");

        // Get the configuration of the H-DMA transfer
        int length = ((value & 0x7f) + 1) * 0x10;
        int source = ((registers[0x51] & 0xff) << 8) | (registers[0x52] & 0xF0);
        int destination =
            ((registers[0x53] & 0x1f) << 8) | (registers[0x54] & 0xF0);

        // H-Blank DMA
        if ((value & 0x80) != 0) {
          dma = DMA(this, source, destination, length);
          registers[MemoryRegisters.hdma] = (length ~/ 0x10 - 1) & 0xFF;
        } else {
          if (dma != null) {
            // print("Terminated DMA from " + source.toString() + "-" + dest.toString() + ", " + length.toString() + " remaining.");
          }

          // General DMA
          for (int i = 0; i < length; i++) {
            vram[vramPageStart + destination + i] = readByte(source + i) & 0xFF;
          }
          registers[MemoryRegisters.hdma] = 0xFF;
        }
      }
    } else if (address == MemoryRegisters.vramBank) {
      if (cpu.cartridge.gameboyType == GameboyType.color) {
        vramPageStart = Memory.vramPageSize * (value & 0x3);
      }
    } else if (address == MemoryRegisters.wramBank) {
      if (cpu.cartridge.gameboyType == GameboyType.color) {
        wramPageStart = Memory.wramPageSize * max(1, value & 0x7);
      }
    } else if (address == MemoryRegisters.nr14) {
      if ((registers[MemoryRegisters.nr14] & 0x80) != 0) {
        //cpu.sound.channel1.restart();
        value &= 0x7f;
      }
    } else if (address == MemoryRegisters.nr10 ||
        address == MemoryRegisters.nr11 ||
        address == MemoryRegisters.nr12 ||
        address == MemoryRegisters.nr13) {
      //cpu.sound.channel1.update();
    } else if (address == MemoryRegisters.nr24) {
      if ((value & 0x80) != 0) {
        //cpu.sound.channel2.restart();
        value &= 0x7F;
      }
    } else if (address == MemoryRegisters.nr21 ||
        address == MemoryRegisters.nr22 ||
        address == MemoryRegisters.nr23) {
      //cpu.sound.channel2.update();
    } else if (address == MemoryRegisters.nr34) {
      if ((value & 0x80) != 0) {
        //cpu.sound.channel3.restart();
        value &= 0x7F;
      }
    } else if (address == MemoryRegisters.nr30 ||
        address == MemoryRegisters.nr31 ||
        address == MemoryRegisters.nr32 ||
        address == MemoryRegisters.nr33) {
      //cpu.sound.channel3.update();
    } else if (address == MemoryRegisters.nr44) {
      if ((value & 0x80) != 0) {
        //cpu.sound.channel4.restart();
        value &= 0x7F;
      }
    } else if (address == MemoryRegisters.nr41 ||
        address == MemoryRegisters.nr42 ||
        address == MemoryRegisters.nr43) {
      //cpu.sound.channel4.update();
    }
    // OAM DMA transfer
    else if (address == MemoryRegisters.dma) {
      int addressBase = value * 0x100;

      for (int i = 0; i < 0xA0; i++) {
        writeByte(0xFE00 + i, readByte(addressBase + i));
      }
    } else if (address == MemoryRegisters.div) {
      value = 0;
    } else if (address == MemoryRegisters.tac) {
      if (((registers[MemoryRegisters.tac] ^ value) & 0x03) != 0) {
        cpu.timerCycle = 0;
        registers[MemoryRegisters.tima] = registers[MemoryRegisters.tma];
      }
    } else if (address == MemoryRegisters.serialSc) {
      // Serial transfer starts if the 7th bit is set
      if (value == 0x81) {
        // Print data passed thought the serial port as character.
        if (Configuration.printSerialCharacters) {
          print(String.fromCharCode(registers[MemoryRegisters.serialSb]));
        }
      }
    } else if (0x30 <= address && address < 0x40) {
      //cpu.sound.channel3.updateSample(address - 0x30, (byte) value);
    }

    registers[address] = value;
  }

  /// Read IO address
  int readIO(int address) {
    if (address > 0xFF) {
      throw Exception(
        'Tring to read register from ${address.toRadixString(16)} (>0xFF).',
      );
    }

    if (address == MemoryRegisters.doubleSpeed) {
      return cpu.doubleSpeed ? 0x80 : 0x0;
    } else if (address == MemoryRegisters.gamepad) {
      int reg = registers[MemoryRegisters.gamepad];
      reg |= 0x0F;

      if (reg & 0x10 == 0) {
        if (cpu.buttons[Gamepad.right]) {
          reg &= ~0x1;
        }
        if (cpu.buttons[Gamepad.left]) {
          reg &= ~0x2;
        }
        if (cpu.buttons[Gamepad.up]) {
          reg &= ~0x4;
        }
        if (cpu.buttons[Gamepad.down]) {
          reg &= ~0x8;
        }
      }

      if (reg & 0x20 == 0) {
        if (cpu.buttons[Gamepad.A]) {
          reg &= ~0x1;
        }
        if (cpu.buttons[Gamepad.B]) {
          reg &= ~0x2;
        }
        if (cpu.buttons[Gamepad.select]) {
          reg &= ~0x4;
        }
        if (cpu.buttons[Gamepad.start]) {
          reg &= ~0x8;
        }
      }

      return reg;
    } else if (address == MemoryRegisters.nr52) {
      int reg = registers[MemoryRegisters.nr52] & 0x80;

      // if(cpu.sound.channel1.isPlaying){reg |= 0x01};
      // if(cpu.sound.channel2.isPlaying){reg |= 0x02};
      // if(cpu.sound.channel3.isPlaying){reg |= 0x04};
      // if(cpu.sound.channel4.isPlaying){reg |= 0x08};

      return reg;
    }

    return registers[address];
  }
}
