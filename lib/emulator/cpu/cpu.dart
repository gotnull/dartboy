import 'dart:convert';

import 'package:dartboy/emulator/audio/apu.dart';
import 'package:dartboy/emulator/configuration.dart';
import 'package:dartboy/emulator/cpu/instructions.dart';
import 'package:dartboy/emulator/cpu/registers.dart';
import 'package:dartboy/emulator/graphics/ppu.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';
import 'package:dartboy/emulator/memory/mmu/mmu.dart';
import 'package:flutter/services.dart';

/// CPU class is responsible for the instruction execution, interrupts, and timing of the system.
///
/// Sharp LR35902
class CPU {
  static const int programCounter = 0;
  static const int stackPointer = 1;

  /// Frequency (hz)
  static const int frequency = 4194304;

  /// Game cartridge memory data composes the lower 32kB of memory from (0x0000 to 0x8000).
  final Cartridge cartridge;

  /// Memory control unit decides from where the addresses are read and written to
  late MMU mmu;

  /// Internal CPU registers
  late Registers registers;

  /// PPU handles the graphics display
  late PPU ppu;

  // Audio handles the audio
  late APU apu;

  /// Whether the CPU is currently halted.
  bool halted;

  /// Whether the CPU should trigger interrupt handlers.
  bool interruptsEnabled;

  bool enableInterruptsNextCycle;

  /// Halt bug flag - when true, PC increment is skipped for next instruction
  bool haltBugTriggered = false;

  /// The current CPU clock cycle since the beginning of the emulation.
  int clocks = 0;

  // Performance optimization counters
  int _ppuUpdateCounter = 0;
  int _apuUpdateCounter = 0;
  int _ppuAccumulatedCycles = 0;
  int _apuAccumulatedCycles = 0;

  /// The number of cycles elapsed since the last speed emulation sleep.
  int cyclesSinceLastSleep = 0;

  /// The number of cycles executed in the last second.
  int cyclesExecutedThisSecond = 0;

  /// Indicates if the emulator is running at double speed.
  bool doubleSpeed;

  int cycles = 0;

  int insCycles = 0;

  /// The current cycle of the DIV register.
  int divCycle = 0;

  /// The current cycle of the TIMA register.
  int timerCycle = 0;

  /// Buttons of the Gameboy, the index stored in the Gamepad class corresponds to the position here
  List<bool> buttons = List.filled(8, false);

  /// Current clock speed of the system (can be double on GBC hardware).
  int clockSpeed = frequency;

  /// Stores the PC and SP pointers
  List<int> pointers = List.filled(2, 0);

  /// 16-bit Program Counter, the memory address of the next instruction to be fetched
  set pc(int value) => pointers[programCounter] = value;

  int get pc => pointers[programCounter];

  /// 16-bit Stack Pointer, the memory address of the top of the stack
  set sp(int value) => pointers[stackPointer] = value;

  int get sp => pointers[stackPointer];

  late Map<String, dynamic> loadedOpcodes;

  Future<Map<String, dynamic>> loadOpcodesBundle() async {
    // Load the JSON file using rootBundle
    final jsonString =
        await rootBundle.loadString('assets/instructions/opcodes.json');
    return jsonDecode(jsonString);
  }

  Future<void> initialize() async {
    loadedOpcodes = await loadOpcodesBundle();
  }

  CPU(this.cartridge)
      : halted = false,
        interruptsEnabled = false,
        enableInterruptsNextCycle = false,
        haltBugTriggered = false,
        doubleSpeed = false {
    mmu = cartridge.createController(this);
    ppu = PPU(this);
    registers = Registers(this);
    apu = APU(clockSpeed);
    apu.updateClockSpeed(clockSpeed); // Ensure Audio clock sync at start

    reset();
  }

  /// Reset the CPU, also resets the MMU, registers and PPU.
  void reset() {
    buttons.fillRange(0, 8, false);

    clockSpeed = frequency;
    apu.updateClockSpeed(clockSpeed); // Ensure Audio is updated after reset

    doubleSpeed = false;
    divCycle = 0;
    timerCycle = 0;
    sp = 0xFFFE;
    pc = 0x0100;

    halted = false;
    interruptsEnabled = false;
    haltBugTriggered = false;

    clocks = 0;
    cyclesSinceLastSleep = 0;
    cyclesExecutedThisSecond = 0;

    registers.reset();
    ppu.reset();
    mmu.reset();
    apu.reset();

    // Note: Window title management removed for cross-platform compatibility
  }

  /// Read the next program byte and update the PC value
  int nextUnsignedBytePC() {
    return getUnsignedByte(pc++);
  }

  /// Read the next program byte and update the PC value
  int nextSignedBytePC() {
    return getSignedByte(pc++);
  }

  /// Read a unsiged byte value from memory.
  int getUnsignedByte(int address) {
    return mmu.readByte(address) & 0xFF;
  }

  /// Read a byte from memory and update the clock count.
  int getSignedByte(int address) {
    return (mmu.readByte(address) & 0xFF).toSigned(8);
  }

  int popByteSP() {
    int value = getUnsignedByte(sp);
    sp = (sp + 1) & 0xFFFF; // SP increments after reading a byte
    return value;
  }

  /// Write a byte into memory (takes 4 clocks)
  void setByte(int address, int value) {
    mmu.writeByte(address, value);
  }

  /// Push word into the temporary stack and update the stack pointer
  void pushWordSP(int value) {
    sp -= 2;
    setByte(sp, value & 0xFF);
    setByte(sp + 1, (value >> 8) & 0xFF);
  }

  int popWordSP() {
    int lo = getUnsignedByte(sp);
    sp = (sp + 1) & 0xFFFF;
    int hi = getUnsignedByte(sp);
    sp = (sp + 1) & 0xFFFF;
    return (hi << 8) | lo;
  }

  /// Increase the clock cycles and trigger interrupts as needed.
  void tick(int delta) {
    clocks += delta;
    cyclesSinceLastSleep += delta;
    cyclesExecutedThisSecond += delta;
    updateInterrupts(delta);
  }

  int getActualClockSpeed() {
    // This could retrieve a clock speed based on system state or configuration
    return doubleSpeed ? frequency * 2 : frequency;
  }

  /// Update interrupt counter, check for interruptions waiting.
  ///
  /// Trigger timer interrupts, LCD updates, and sound updates as needed.
  ///
  /// @param delta CPU cycles elapsed since the last call to this method
  void updateInterrupts(int delta) {
    if (doubleSpeed) {
      delta ~/= 2;
    }

    // The DIV register increments at 16KHz, and resets to 0 after
    divCycle += delta;

    if (divCycle >= 256) {
      divCycle -= 256;

      mmu.writeRegisterByte(
          MemoryRegisters.div, mmu.readRegisterByte(MemoryRegisters.div) + 1);
    }

    // The Timer is similar to DIV, except that when it overflows it triggers an interrupt
    int tac = mmu.readRegisterByte(MemoryRegisters.tac);

    // If timer 3 bit is set the timer should start
    if ((tac & 0x4) != 0) {
      timerCycle += delta;

      // The Timer has a settable frequency
      int timerPeriod = 0;

      switch (tac & 0x3) {
        // 4096 Hz
        case 0x0:
          timerPeriod = getActualClockSpeed() ~/ 4096;
          break;

        // 262144 Hz
        case 0x1:
          timerPeriod = getActualClockSpeed() ~/ 262144;
          break;

        // 65536 Hz
        case 0x2:
          timerPeriod = getActualClockSpeed() ~/ 65536;
          break;

        // 16384 Hz
        case 0x3:
          timerPeriod = getActualClockSpeed() ~/ 16384;
          break;
      }

      while (timerCycle >= timerPeriod) {
        timerCycle -= timerPeriod;

        // And it resets to a specific value
        int tima = (mmu.readRegisterByte(MemoryRegisters.tima) & 0xFF) + 1;

        if (tima > 0xFF) {
          tima = mmu.readRegisterByte(MemoryRegisters.tma) & 0xFF;
          setInterruptTriggered(MemoryRegisters.timerOverflowBit);
        }

        mmu.writeRegisterByte(MemoryRegisters.tima, tima & 0xFF);
      }
    }

    // Performance optimization: batch PPU/APU updates
    if (Configuration.mobileOptimization) {
      _ppuAccumulatedCycles += delta;
      _apuAccumulatedCycles += delta;
      
      _ppuUpdateCounter++;
      if (_ppuUpdateCounter >= Configuration.ppuUpdateFrequency) {
        ppu.tick(_ppuAccumulatedCycles);
        _ppuAccumulatedCycles = 0;
        _ppuUpdateCounter = 0;
      }
      
      _apuUpdateCounter++;
      if (_apuUpdateCounter >= Configuration.apuUpdateFrequency) {
        apu.tick(_apuAccumulatedCycles);
        _apuAccumulatedCycles = 0;
        _apuUpdateCounter = 0;
      }
    } else {
      ppu.tick(delta);
      apu.tick(delta);
    }
  }

  /// Flush any remaining accumulated cycles to PPU/APU (called at frame end)
  void flushPendingUpdates() {
    if (Configuration.mobileOptimization) {
      if (_ppuAccumulatedCycles > 0) {
        ppu.tick(_ppuAccumulatedCycles);
        _ppuAccumulatedCycles = 0;
        _ppuUpdateCounter = 0;
      }
      if (_apuAccumulatedCycles > 0) {
        apu.tick(_apuAccumulatedCycles);
        _apuAccumulatedCycles = 0;
        _apuUpdateCounter = 0;
      }
    }
  }

  /// Triggers a particular interrupt by writing the correct interrupt bit to the interrupt register.
  ///
  /// @param interrupt The interrupt bit.
  void setInterruptTriggered(int interrupt) {
    mmu.writeRegisterByte(MemoryRegisters.triggeredInterrupts,
        mmu.readRegisterByte(MemoryRegisters.triggeredInterrupts) | interrupt);
  }

  // Auxiliary method to check if an interruption was triggered.
  bool interruptTriggered(int interrupt) {
    return (mmu.readRegisterByte(MemoryRegisters.triggeredInterrupts) &
            mmu.readRegisterByte(MemoryRegisters.enabledInterrupts) &
            interrupt) !=
        0;
  }

  /// Fires interrupts if interrupts are enabled.
  bool fireInterrupts() {
    int triggeredInterrupts = mmu.readRegisterByte(
      MemoryRegisters.triggeredInterrupts,
    );

    int enabledInterrupts = mmu.readRegisterByte(
      MemoryRegisters.enabledInterrupts,
    );

    // Check if any interrupt is triggered and enabled
    int pendingInterrupts = triggeredInterrupts & enabledInterrupts;

    if (pendingInterrupts != 0) {
      // If interrupts are enabled, handle the interrupt
      if (interruptsEnabled) {
        pushWordSP(pc);
        interruptsEnabled = false;

        // Handle interrupts in priority order
        if ((pendingInterrupts & MemoryRegisters.vblankBit) != 0) {
          pc = MemoryRegisters.vblankHandlerAddress;
          triggeredInterrupts &= ~MemoryRegisters.vblankBit;
        } else if ((pendingInterrupts & MemoryRegisters.lcdcBit) != 0) {
          pc = MemoryRegisters.lcdcHandlerAddress;
          triggeredInterrupts &= ~MemoryRegisters.lcdcBit;
        } else if ((pendingInterrupts & MemoryRegisters.timerOverflowBit) !=
            0) {
          pc = MemoryRegisters.timerOverflowHandlerAddress;
          triggeredInterrupts &= ~MemoryRegisters.timerOverflowBit;
        } else if ((pendingInterrupts & MemoryRegisters.serialTransferBit) !=
            0) {
          pc = MemoryRegisters.serialTransferHandlerAddress;
          triggeredInterrupts &= ~MemoryRegisters.serialTransferBit;
        } else if ((pendingInterrupts & MemoryRegisters.hiloBit) != 0) {
          pc = MemoryRegisters.hiloHandlerAddress;
          triggeredInterrupts &= ~MemoryRegisters.hiloBit;
        }

        mmu.writeRegisterByte(
          MemoryRegisters.triggeredInterrupts,
          triggeredInterrupts,
        );

        return true;
      }
    }

    return false;
  }

  /// Next step in the CPU processing, should be called at a fixed rate.
  int cycle() {
    cycles++;

    int ie = mmu.readRegisterByte(MemoryRegisters.enabledInterrupts);
    int ifr = mmu.readRegisterByte(MemoryRegisters.triggeredInterrupts);

    if (halted) {
      // Check for pending interrupts (enabled AND triggered)
      int pendingInterrupts = ie & ifr;

      if (pendingInterrupts != 0) {
        // Exit halt if any interrupt is pending
        halted = false;
      } else {
        // No interrupts pending, stay halted
        tick(4); // Consume 4 cycles while halted
        return 4;
      }
    }

    if (interruptsEnabled && fireInterrupts()) {
      return 20; // Interrupt handling takes 20 cycles (5 memory accesses * 4 cycles each)
    }

    // Handle halt bug: PC increment is skipped for the opcode fetch only
    int op = getUnsignedByte(pc);
    if (!haltBugTriggered) {
      pc++;
    } else {
      haltBugTriggered = false; // Reset after affecting one opcode fetch
    }

    int cyclesUsed = executeInstruction(op);

    return cyclesUsed;
  }

  int checkCBCycleCount(int op) {
    int cycle = 0;
    String opcodeKey =
        '0x${op.toRadixString(16).toUpperCase().padLeft(2, '0')}';
    Map<String, dynamic>? opcodeDetails =
        loadedOpcodes['cbprefixed']?[opcodeKey];

    if (opcodeDetails != null) {
      List<int> expectedCycles = List<int>.from(opcodeDetails['cycles']);
      cycle = expectedCycles[0];
    } else {
      print('CB Opcode $opcodeKey not found in opcodes.json');
    }

    return cycle;
  }

  int checkCycleCount(int op, [bool condition = false]) {
    int cycle = 0;

    bool isCBPrefix = op == 0xCB;
    String opcodeKey = isCBPrefix
        ? '0x${(op & 0xFF).toRadixString(16).toUpperCase().padLeft(2, '0')}'
        : '0x${op.toRadixString(16).toUpperCase().padLeft(2, '0')}';

    Map<String, dynamic>? opcodeDetails;

    if (isCBPrefix) {
      opcodeDetails = loadedOpcodes['cbprefixed']?[opcodeKey];
    } else {
      opcodeDetails = loadedOpcodes['unprefixed']?[opcodeKey];
    }

    if (opcodeDetails != null) {
      List<int> expectedCycles = List<int>.from(opcodeDetails['cycles']);
      cycle = condition && expectedCycles.length > 1
          ? expectedCycles[1]
          : expectedCycles[0];
    } else {
      print('Opcode $opcodeKey not found in opcodes.json');
    }

    return cycle;
  }

  int executeInstruction(int op) {
    int cyclesForOp = 0;

    switch (op) {
      case 0x00:
        cyclesForOp = checkCycleCount(op);
        Instructions.nop(this);
        break;
      case 0xC4:
      case 0xCC:
      case 0xD4:
      case 0xDC:
        bool conditionMet = Instructions.callccnn(this, op);
        cyclesForOp = checkCycleCount(op, !conditionMet);
        break;
      case 0xCD:
        cyclesForOp = checkCycleCount(op);
        Instructions.callnn(this);
        break;
      case 0x01:
      case 0x11:
      case 0x21:
      case 0x31:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldddnn(this, op);
        break;
      case 0x06:
      case 0x0E:
      case 0x16:
      case 0x1E:
      case 0x26:
      case 0x2E:
      case 0x36:
      case 0x3E:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldrn(this, op);
        break;
      case 0x0A:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldabc(this);
        break;
      case 0x1A:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldade(this);
        break;
      case 0x02:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldcba(this);
        break;
      case 0x12:
        cyclesForOp = checkCycleCount(op);
        Instructions.lddea(this);
        break;
      case 0xF2:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldac(this);
        break;
      case 0xE8:
        cyclesForOp = checkCycleCount(op);
        Instructions.addspn(this);
        break;
      case 0x37:
        cyclesForOp = checkCycleCount(op);
        Instructions.scf(this);
        break;
      case 0x3F:
        cyclesForOp = checkCycleCount(op);
        Instructions.ccf(this);
        break;
      case 0x3A:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldan(this);
        break;
      case 0xEA:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldnna(this);
        break;
      case 0xF8:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldhlspn(this);
        break;
      case 0x2F:
        cyclesForOp = checkCycleCount(op);
        Instructions.cpl(this);
        break;
      case 0xE0:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldffna(this);
        break;
      case 0xE2:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldhffca(this);
        break;
      case 0xFA:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldann(this);
        break;
      case 0x2A:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldahli(this);
        break;
      case 0x22:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldhlia(this);
        break;
      case 0x32:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldhlda(this);
        break;
      case 0x10:
        cyclesForOp = checkCycleCount(op);
        Instructions.stop(this);
        break;
      case 0xF9:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldsphl(this);
        break;
      case 0xC5:
      case 0xD5:
      case 0xE5:
      case 0xF5:
        cyclesForOp = checkCycleCount(op);
        Instructions.pushrr(this, op);
        break;
      case 0xC1:
      case 0xD1:
      case 0xE1:
      case 0xF1:
        cyclesForOp = checkCycleCount(op);
        Instructions.poprr(this, op);
        break;
      case 0x08:
        cyclesForOp = checkCycleCount(op);
        Instructions.lda16sp(this);
        break;
      case 0xD9:
        cyclesForOp = checkCycleCount(op);
        Instructions.reti(this);
        break;
      case 0xC3:
        cyclesForOp = checkCycleCount(op);
        Instructions.jpnn(this);
        break;
      case 0x07:
        cyclesForOp = checkCycleCount(op);
        Instructions.rlca(this);
        break;
      case 0x3C:
      case 0x04:
      case 0x0C:
      case 0x14:
      case 0x1C:
      case 0x24:
      case 0x34:
      case 0x2C:
        cyclesForOp = checkCycleCount(op);
        Instructions.incr(this, op);
        break;
      case 0x3D:
      case 0x05:
      case 0x0D:
      case 0x15:
      case 0x1D:
      case 0x25:
      case 0x2D:
      case 0x35:
        cyclesForOp = checkCycleCount(op);
        Instructions.decr(this, op);
        break;
      case 0x03:
      case 0x13:
      case 0x23:
      case 0x33:
        cyclesForOp = checkCycleCount(op);
        Instructions.incrr(this, op);
        break;
      case 0xB8:
      case 0xB9:
      case 0xBA:
      case 0xBB:
      case 0xBC:
      case 0xBD:
      case 0xBE:
      case 0xBF:
        cyclesForOp = checkCycleCount(op);
        Instructions.cprr(this, op);
        break;
      case 0xFE:
        cyclesForOp = checkCycleCount(op);
        Instructions.cpn(this);
        break;
      case 0x09:
      case 0x19:
      case 0x29:
      case 0x39:
        cyclesForOp = checkCycleCount(op);
        Instructions.addhlrr(this, op);
        break;
      case 0xE9:
        cyclesForOp = checkCycleCount(op);
        Instructions.jphl(this);
        break;
      case 0xDE:
        cyclesForOp = checkCycleCount(op);
        Instructions.sbcn(this);
        break;
      case 0xD6:
        cyclesForOp = checkCycleCount(op);
        Instructions.subn(this);
        break;
      case 0x90:
      case 0x91:
      case 0x92:
      case 0x93:
      case 0x94:
      case 0x95:
      case 0x96:
      case 0x97:
        cyclesForOp = checkCycleCount(op);
        Instructions.subr(this, op);
        break;
      case 0xC6:
        cyclesForOp = checkCycleCount(op);
        Instructions.addn(this);
        break;
      case 0x87:
      case 0x80:
      case 0x81:
      case 0x82:
      case 0x83:
      case 0x84:
      case 0x85:
      case 0x86:
        cyclesForOp = checkCycleCount(op);
        Instructions.addr(this, op);
        break;
      case 0x88:
      case 0x89:
      case 0x8A:
      case 0x8B:
      case 0x8C:
      case 0x8E:
      case 0x8D:
      case 0x8F:
        cyclesForOp = checkCycleCount(op);
        Instructions.adcr(this, op);
        break;
      case 0xA0:
      case 0xA1:
      case 0xA2:
      case 0xA3:
      case 0xA4:
      case 0xA5:
      case 0xA6:
      case 0xA7:
        cyclesForOp = checkCycleCount(op);
        Instructions.andr(this, op);
        break;
      case 0xA8:
      case 0xA9:
      case 0xAA:
      case 0xAB:
      case 0xAC:
      case 0xAD:
      case 0xAE:
      case 0xAF:
        cyclesForOp = checkCycleCount(op);
        Instructions.xorr(this, op);
        break;
      case 0xF6:
        cyclesForOp = checkCycleCount(op);
        Instructions.orn(this);
        break;
      case 0xB0:
      case 0xB1:
      case 0xB2:
      case 0xB3:
      case 0xB4:
      case 0xB5:
      case 0xB6:
      case 0xB7:
        cyclesForOp = checkCycleCount(op);
        Instructions.orr(this, op);
        break;
      case 0x18:
        cyclesForOp = checkCycleCount(op);
        Instructions.jre(this);
        break;
      case 0x27:
        cyclesForOp = checkCycleCount(op);
        Instructions.daa(this);
        break;
      case 0xCA:
      case 0xC2:
      case 0xDA:
      case 0xD2:
        bool conditionMet = Instructions.jpcnn(this, op);
        cyclesForOp = checkCycleCount(op, !conditionMet);
        break;
      case 0x20:
      case 0x28:
      case 0x30:
      case 0x38:
        bool conditionMet = Instructions.jrce(this, op);
        cyclesForOp = checkCycleCount(op, !conditionMet);
        break;
      case 0xF0:
        cyclesForOp = checkCycleCount(op);
        Instructions.ldhffnn(this);
        break;
      case 0x76:
        cyclesForOp = checkCycleCount(op);
        Instructions.halt(this);
        break;
      case 0xC0:
      case 0xC8:
      case 0xD0:
      case 0xD8:
        bool conditionMet = Instructions.retc(this, op);
        cyclesForOp = checkCycleCount(op, !conditionMet);
        break;
      case 0xC7:
      case 0xCF:
      case 0xD7:
      case 0xDF:
      case 0xE7:
      case 0xEF:
      case 0xF7:
      case 0xFF:
        cyclesForOp = checkCycleCount(op);
        Instructions.rstp(this, op);
        break;
      case 0xF3:
        cyclesForOp = checkCycleCount(op);
        Instructions.di(this);
        break;
      case 0xFB:
        cyclesForOp = checkCycleCount(op);
        Instructions.ei(this);
        break;
      case 0xE6:
        cyclesForOp = checkCycleCount(op);
        Instructions.andn(this);
        break;
      case 0xEE:
        cyclesForOp = checkCycleCount(op);
        Instructions.xorn(this);
        break;
      case 0xC9:
        cyclesForOp = checkCycleCount(op);
        Instructions.ret(this);
        break;
      case 0xCE:
        cyclesForOp = checkCycleCount(op);
        Instructions.adcn(this);
        break;
      case 0x98:
      case 0x99:
      case 0x9A:
      case 0x9B:
      case 0x9C:
      case 0x9D:
      case 0x9E:
      case 0x9F:
        cyclesForOp = checkCycleCount(op);
        Instructions.sbcr(this, op);
        break;
      case 0x0F:
        cyclesForOp = checkCycleCount(op);
        Instructions.rrca(this);
        break;
      case 0x1F:
        cyclesForOp = checkCycleCount(op);
        Instructions.rra(this);
        break;
      case 0x17:
        cyclesForOp = checkCycleCount(op);
        Instructions.rla(this);
        break;
      case 0x0B:
      case 0x1B:
      case 0x2B:
      case 0x3B:
        cyclesForOp = checkCycleCount(op);
        Instructions.decrr(this, op);
        break;
      case 0xCB:
        cyclesForOp = Instructions.cbprefix(this);
        break;
      default:
        switch (op & 0xC0) {
          case 0x40:
            cyclesForOp = checkCycleCount(op);
            Instructions.ldrr(this, op);
            break;
          default:
            print('Unsupported operation, (OP: 0x${op.toRadixString(16)})');
            break;
        }
        break;
    }

    // Enable interrupts if needed after each instruction
    if (enableInterruptsNextCycle) {
      interruptsEnabled = true;
      enableInterruptsNextCycle = false;
    }

    // Advance the CPU clock by the cycles required for the executed instruction.
    tick(cyclesForOp);

    // Return the cycles used for this instruction.
    return cyclesForOp;
  }

  /// Puts the emulator in and out of double speed mode.
  ///
  /// @param doubleSpeed the new double speed state
  void setDoubleSpeed(bool newDoubleSpeed) {
    if (doubleSpeed != newDoubleSpeed) {
      doubleSpeed = newDoubleSpeed;
      clockSpeed = getActualClockSpeed(); // Update the current clock speed
      apu.updateClockSpeed(clockSpeed); // Update audio's clock speed
    }
  }

  /// Returns a string with debug information on the current status of the CPU.
  ///
  /// Returns the current values of all registers, and a history of the instructions executed by the CPU.
  String getDebugString() {
    String data = 'Registers:\n';
    /* data += 'AF: 0x' + registers.af.toRadixString(16) + '\n';
    data += 'BC: 0x' + registers.bc.toRadixString(16) + '\n';
    data += 'DE: 0x' + registers.de.toRadixString(16) + '\n';
    data += 'HL: 0x' + registers.hl.toRadixString(16) + '\n';*/

    data += 'CPU:\n';
    data += 'PC: 0x${pc.toRadixString(16)}\n';
    data += 'SP: 0x${sp.toRadixString(16)}\n';
    data += 'Clocks: $clocks\n';

    return data;
  }
}
