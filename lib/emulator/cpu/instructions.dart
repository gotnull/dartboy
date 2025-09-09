import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/cpu/registers.dart';
import 'package:dartboy/emulator/memory/memory_addresses.dart';

/// Class to handle instruction implementation, instructions run on top of the CPU object.
///
/// This class is just an abstraction to make the CPU structure cleaner.
class Instructions {
  static String extendStr(String value, int length) {
    for (int i = value.length - 1; i < length; i++) {
      value += ' ';
    }

    return value;
  }

  static void nop(CPU cpu) {}

  static bool callccnn(CPU cpu, int op) {
    int addr = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    int conditionCode = (op >> 3) & 0x03; // Extract condition code
    bool conditionMet = cpu.registers.checkCondition(conditionCode);
    if (conditionMet) {
      cpu.pushWordSP(cpu.pc);
      cpu.pc = addr;
    }
    return conditionMet;
  }

  static void callnn(CPU cpu) {
    int jmp = (cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8));
    cpu.pushWordSP(cpu.pc); // Push the current PC to the stack
    cpu.pc = jmp;
  }

  static void ldddnn(CPU cpu, int op) {
    cpu.registers.setRegisterPairSP((op >> 4) & 0x3,
        cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8));
  }

  static void ldrn(CPU cpu, int op) {
    int to = (op >> 3) & 0x7;
    int n = cpu.nextUnsignedBytePC();
    cpu.registers.setRegister(to, n);
  }

  static void ldabc(CPU cpu) {
    cpu.registers.a =
        cpu.getUnsignedByte(cpu.registers.getRegisterPairSP(Registers.bc));
  }

  static void ldade(CPU cpu) {
    cpu.registers.a =
        cpu.getUnsignedByte(cpu.registers.getRegisterPairSP(Registers.de));
  }

  static void ldcba(CPU cpu) {
    cpu.mmu.writeByte(
        cpu.registers.getRegisterPairSP(Registers.bc), cpu.registers.a);
  }

  static void lddea(CPU cpu) {
    cpu.mmu.writeByte(
        cpu.registers.getRegisterPairSP(Registers.de), cpu.registers.a);
  }

  static void ldac(CPU cpu) {
    cpu.registers.a =
        cpu.mmu.readByte(MemoryAddresses.ioStart | cpu.registers.c);
  }

  static void addspn(CPU cpu) {
    int offset = cpu.nextSignedBytePC();
    int nsp = (cpu.sp + offset);

    cpu.registers.f = 0;
    int carry = nsp ^ cpu.sp ^ offset;

    if ((carry & 0x100) != 0) {
      cpu.registers.f |= Registers.carryFlag;
    }

    if ((carry & 0x10) != 0) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    nsp &= 0xFFFF;

    cpu.sp = nsp;
  }

  static void scf(CPU cpu) {
    cpu.registers.f &= Registers.zeroFlag; // Keep zero flag unchanged
    cpu.registers.f |= Registers.carryFlag; // Set carry flag
    cpu.registers.f &= ~Registers.subtractFlag; // Clear subtract flag
    cpu.registers.f &= ~Registers.halfCarryFlag; // Clear half-carry flag
  }

  static void ccf(CPU cpu) {
    cpu.registers.f = (cpu.registers.f & Registers.carryFlag) != 0
        ? (cpu.registers.f & Registers.zeroFlag)
        : ((cpu.registers.f & Registers.zeroFlag) | Registers.carryFlag);
  }

  static void ldan(CPU cpu) {
    cpu.registers.a = cpu.getUnsignedByte(
        cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) - 1) & 0xFFFF);
  }

  static void ldnna(CPU cpu) {
    int address = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    cpu.mmu.writeByte(address, cpu.registers.a);
  }

  static void ldhlspn(CPU cpu) {
    int offset = cpu.nextSignedBytePC();
    int nsp = (cpu.sp + offset);

    cpu.registers.f = 0; // (short) (cpu.registers.f & Registers.F_ZERO);
    int carry = nsp ^ cpu.sp ^ offset;

    if ((carry & 0x100) != 0) {
      cpu.registers.f |= Registers.carryFlag;
    }
    if ((carry & 0x10) != 0) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    nsp &= 0xFFFF;
    cpu.registers.setRegisterPairSP(Registers.hl, nsp);
  }

  static void cpl(CPU cpu) {
    cpu.registers.a = (~cpu.registers.a) & 0xFF;
    cpu.registers.f =
        (cpu.registers.f & (Registers.carryFlag | Registers.zeroFlag)) |
            Registers.halfCarryFlag |
            Registers.subtractFlag;
  }

  static void ldffna(CPU cpu) {
    cpu.mmu.writeByte(
        MemoryAddresses.ioStart | cpu.nextUnsignedBytePC(), cpu.registers.a);
  }

  static void ldhffca(CPU cpu) {
    cpu.mmu.writeByte(
        MemoryAddresses.ioStart | (cpu.registers.c & 0xFF), cpu.registers.a);
  }

  static void ldann(CPU cpu) {
    int nn = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    cpu.registers.a = cpu.getUnsignedByte(nn);
  }

  static void ldahli(CPU cpu) {
    cpu.registers.a = cpu.getUnsignedByte(
        cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) + 1) & 0xFFFF);
  }

  static void ldhlia(CPU cpu) {
    cpu.mmu.writeByte(cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF,
        cpu.registers.a);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) + 1) & 0xFFFF);
  }

  static void ldhlda(CPU cpu) {
    int hl = cpu.registers.getRegisterPairSP(Registers.hl);
    cpu.mmu.writeByte(hl, cpu.registers.a);

    cpu.registers.setRegisterPairSP(Registers.hl, (hl - 1) & 0xFFFF);
  }

  static void stop(CPU cpu) {
    nop(cpu);
  }

  static void ldrr(CPU cpu, int op) {
    int from = op & 0x7;
    int to = (op >> 3) & 0x7;

    if (from == 6) {
      // Handle LD r, (HL)
      int hl = cpu.registers.getRegisterPairSP(Registers.hl);
      int value = cpu.getUnsignedByte(hl);
      cpu.registers.setRegister(to, value);
    } else if (to == 6) {
      // Handle LD (HL), r
      int hl = cpu.registers.getRegisterPairSP(Registers.hl);
      int value = cpu.registers.getRegister(from);
      cpu.setByte(hl, value);
    } else {
      // Handle LD r, r
      int value = cpu.registers.getRegister(from);
      cpu.registers.setRegister(to, value);
    }
  }

  static int cbprefix(CPU cpu) {
    int op = cpu.getUnsignedByte(cpu.pc++);
    int reg = op & 0x7;
    int data = cpu.registers.getRegister(reg) & 0xFF;

    switch (op & 0xC0) {
      case 0x80:
        {
          // RES b, r
          // 1 0 b b b r r r
          cpu.registers.setRegister(reg, data & ~(0x1 << (op >> 3 & 0x7)));
        }
        break;
      case 0xC0:
        {
          // SET b, r
          // 1 1 b b b r r r
          cpu.registers.setRegister(reg, data | (0x1 << (op >> 3 & 0x7)));
        }
        break;
      case 0x40:
        {
          // BIT b, r
          // 0 1 b b b r r r
          cpu.registers.f &= Registers.carryFlag;
          cpu.registers.f |= Registers.halfCarryFlag;
          if ((data & (0x1 << (op >> 3 & 0x7))) == 0) {
            cpu.registers.f |= Registers.zeroFlag;
          }
        }
        break;
      case 0x0:
        {
          switch (op & 0xf8) {
            case 0x00: // RLcpu.registers.c m
              {
                cpu.registers.f = 0;
                if ((data & 0x80) != 0) {
                  cpu.registers.f |= Registers.carryFlag;
                }
                data <<= 1;

                // we're shifting circular left, add back bit 7
                if ((cpu.registers.f & Registers.carryFlag) != 0) {
                  data |= 0x01;
                }

                data &= 0xFF;

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x08: // RRcpu.registers.c m
              {
                cpu.registers.f = 0;
                if ((data & 0x1) != 0) {
                  cpu.registers.f |= Registers.carryFlag;
                }

                data >>= 1;

                // we're shifting circular right, add back bit 7
                if ((cpu.registers.f & Registers.carryFlag) != 0) {
                  data |= 0x80;
                }

                data &= 0xFF;

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x10: // Rcpu.registers.l m
              {
                bool carryflag = (cpu.registers.f & Registers.carryFlag) != 0;
                cpu.registers.f = 0;

                // we'll be shifting left, so if bit 7 is set we set carry
                if ((data & 0x80) == 0x80) {
                  cpu.registers.f |= Registers.carryFlag;
                }
                data <<= 1;
                data &= 0xFF;

                // move old cpu.registers.c into bit 0
                if (carryflag) {
                  data |= 0x1;
                }

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x18: // RR m
              {
                bool carryflag = (cpu.registers.f & Registers.carryFlag) != 0;
                cpu.registers.f = 0;

                // we'll be shifting right, so if bit 1 is set we set carry
                if ((data & 0x1) == 0x1) {
                  cpu.registers.f |= Registers.carryFlag;
                }

                data >>= 1;

                // move old cpu.registers.c into bit 7
                if (carryflag) {
                  data |= 0x80;
                }

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x38: // SRcpu.registers.l m
              {
                cpu.registers.f = (data & 0x1) != 0 ? Registers.carryFlag : 0;
                data >>= 1;
                cpu.registers.f |= (data == 0 ? Registers.zeroFlag : 0);
                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x20: // SLcpu.registers.a m
              {
                cpu.registers.f = 0;

                // we'll be shifting right, so if bit 1 is set we set carry
                if ((data & 0x80) != 0) {
                  cpu.registers.f |= Registers.carryFlag;
                }

                data <<= 1;
                data &= 0xFF;

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x28: // SRcpu.registers.a m
              {
                bool bit7 = (data & 0x80) != 0;
                cpu.registers.f = 0;
                if ((data & 0x1) != 0) {
                  cpu.registers.f |= Registers.carryFlag;
                }

                data >>= 1;

                if (bit7) {
                  data |= 0x80;
                }

                if (data == 0) {
                  cpu.registers.f |= Registers.zeroFlag;
                }

                cpu.registers.setRegister(reg, data);
              }
              break;
            case 0x30: // SWAP B (0x30)
              data = ((data & 0xF0) >> 4) | ((data & 0x0F) << 4);
              cpu.registers.setRegister(reg, data);
              cpu.registers.f = data == 0 ? Registers.zeroFlag : 0;
              break;
            default:
              throw Exception(
                "CB Prefix 0xf8 operation unknown 0x${op.toRadixString(16)}",
              );
          }
          break;
        }
      default:
        throw Exception(
          "CB Prefix operation unknown 0x${op.toRadixString(16)}",
        );
    }
    return cpu.checkCycleCount(op, true);
  }

  static void decrr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;
    int o = cpu.registers.getRegisterPairSP(pair);
    cpu.registers.setRegisterPairSP(pair, (o - 1) & 0xFFFF);
  }

  static void rla(CPU cpu) {
    int carry = (cpu.registers.f & Registers.carryFlag) != 0 ? 1 : 0;
    bool newCarry = (cpu.registers.a & 0x80) != 0; // Check bit 7
    cpu.registers.a =
        ((cpu.registers.a << 1) & 0xFF) | carry; // Shift left and add old carry
    cpu.registers.f &=
        ~Registers.zeroFlag; // Clear zero flag, since RLA never sets it
    cpu.registers.f &= ~Registers.subtractFlag; // Clear subtract flag
    cpu.registers.f &= ~Registers.halfCarryFlag; // Clear half-carry flag
    if (newCarry) {
      cpu.registers.f |= Registers.carryFlag; // Set new carry flag
    } else {
      cpu.registers.f &= ~Registers.carryFlag; // Clear carry flag
    }
  }

  static void rra(CPU cpu) {
    int carry = (cpu.registers.f & Registers.carryFlag) != 0 ? 0x80 : 0;
    bool newCarry = (cpu.registers.a & 0x01) != 0; // Check bit 0
    cpu.registers.a = ((cpu.registers.a >> 1) & 0xFF) |
        carry; // Shift right and add old carry
    cpu.registers.f &=
        ~Registers.zeroFlag; // Clear zero flag, since RRA never sets it
    cpu.registers.f &= ~Registers.subtractFlag; // Clear subtract flag
    cpu.registers.f &= ~Registers.halfCarryFlag; // Clear half-carry flag
    if (newCarry) {
      cpu.registers.f |= Registers.carryFlag; // Set new carry flag
    } else {
      cpu.registers.f &= ~Registers.carryFlag; // Clear carry flag
    }
  }

  static void rrca(CPU cpu) {
    bool carry = (cpu.registers.a & 0x01) != 0; // Check bit 0 for carry
    cpu.registers.a = ((cpu.registers.a >> 1) | (carry ? 0x80 : 0)) &
        0xFF; // Rotate right circular

    cpu.registers.f = 0; // Clear all flags
    if (carry) {
      cpu.registers.f |= Registers.carryFlag; // Set carry flag if bit 0 was set
    }
  }

  static void sbcr(CPU cpu, int op) {
    int carry = (cpu.registers.f & Registers.carryFlag) != 0 ? 1 : 0;
    int reg = cpu.registers.getRegister(op & 0x7) & 0xFF;
    int result = cpu.registers.a - reg - carry;

    cpu.registers.f = Registers.subtractFlag; // Set subtract flag

    if (((cpu.registers.a & 0xF) - (reg & 0xF) - carry) < 0) {
      cpu.registers.f |= Registers.halfCarryFlag; // Set half-carry flag
    }

    if (result < 0) {
      cpu.registers.f |=
          Registers.carryFlag; // Set carry flag if result is negative
    }

    cpu.registers.a = result & 0xFF; // Store result back in A

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag; // Set zero flag if result is zero
    }
  }

  static void adcn(CPU cpu) {
    int val = cpu.nextUnsignedBytePC();
    int carry = ((cpu.registers.f & Registers.carryFlag) != 0 ? 1 : 0);
    int result = cpu.registers.a + val + carry;

    cpu.registers.f = 0; // Reset flags

    if (((cpu.registers.a & 0xF) + (val & 0xF) + carry) > 0xF) {
      cpu.registers.f |= Registers.halfCarryFlag; // Set half-carry flag
    }

    if (result > 0xFF) {
      cpu.registers.f |=
          Registers.carryFlag; // Set carry flag if result exceeds 255
    }

    cpu.registers.a = result & 0xFF; // Store lower 8 bits of result in A

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag; // Set zero flag if result is zero
    }
  }

  static void ret(CPU cpu) {
    cpu.pc = cpu.popWordSP(); // Pop return address into PC
  }

  static void xorn(CPU cpu) {
    int value = cpu.nextUnsignedBytePC(); // Fetch immediate value
    cpu.registers.a ^= value; // XOR A with immediate value
    cpu.registers.f = 0; // Reset flags

    if (cpu.registers.a == 0) {
      // Set zero flag if result is 0
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void andn(CPU cpu) {
    int value = cpu.nextUnsignedBytePC(); // Fetch immediate value
    cpu.registers.a &= value; // AND A with immediate value
    cpu.registers.f = Registers.halfCarryFlag; // Always set the half-carry flag

    if (cpu.registers.a == 0) {
      // Set zero flag if result is 0
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void ei(CPU cpu) {
    cpu.enableInterruptsNextCycle =
        true; // Enable interrupts after the next instruction
  }

  static void di(CPU cpu) {
    // Just disabling interrupts, no delay needed
    cpu.interruptsEnabled = false;
  }

  static void rstp(CPU cpu, int op) {
    cpu.pushWordSP(cpu.pc); // Save current PC on the stack
    cpu.pc = op & 0x38; // Jump to the specific reset vector
  }

  static bool retc(CPU cpu, int op) {
    int conditionCode = (op >> 3) & 0x03; // Extract condition code
    bool conditionMet = cpu.registers.checkCondition(conditionCode);
    if (conditionMet) {
      cpu.pc = cpu.popWordSP();
    }
    return conditionMet;
  }

  static void halt(CPU cpu) {
    cpu.halted = true;
  }

  static void ldhffnn(CPU cpu) {
    cpu.registers.a =
        cpu.getUnsignedByte(MemoryAddresses.ioStart | cpu.nextUnsignedBytePC());
  }

  static bool jrce(CPU cpu, int op) {
    int e = cpu.nextSignedBytePC();
    int conditionCode = (op >> 3) & 0x03; // Extract condition code
    bool conditionMet = cpu.registers.checkCondition(conditionCode);
    if (conditionMet) {
      cpu.pc = (cpu.pc + e) & 0xFFFF;
    }
    return conditionMet;
  }

  static bool jpcnn(CPU cpu, int op) {
    int addr = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    int conditionCode = (op >> 3) & 0x03; // Extract condition code
    bool conditionMet = cpu.registers.checkCondition(conditionCode);
    if (conditionMet) {
      cpu.pc = addr;
    }
    return conditionMet;
  }

  static void daa(CPU cpu) {
    int a = cpu.registers.a;
    int correction = 0;

    bool carry = false;

    // If in subtraction mode, undo the correction for previous addition
    if ((cpu.registers.f & Registers.subtractFlag) != 0) {
      if ((cpu.registers.f & Registers.halfCarryFlag) != 0) {
        correction |= 0x06;
      }
      if ((cpu.registers.f & Registers.carryFlag) != 0) {
        correction |= 0x60;
        carry = true;
      }
      a -= correction;
    } else {
      // Addition mode
      if ((cpu.registers.f & Registers.halfCarryFlag) != 0 || (a & 0x0F) > 9) {
        correction |= 0x06;
      }
      if ((cpu.registers.f & Registers.carryFlag) != 0 || a > 0x99) {
        correction |= 0x60;
        carry = true;
      }
      a += correction;
    }

    a &= 0xFF; // Limit to 8 bits

    // Update flags
    cpu.registers.f &= ~(Registers.halfCarryFlag |
        Registers.zeroFlag |
        Registers.carryFlag); // Clear the flags
    if (carry) {
      cpu.registers.f |= Registers.carryFlag;
    }
    if (a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }

    cpu.registers.a = a; // Store the final value of A
  }

  static void jre(CPU cpu) {
    int e = cpu.nextSignedBytePC();
    cpu.pc += e;
  }

  static void or(CPU cpu, int n) {
    cpu.registers.a |= n;
    cpu.registers.f = 0;
    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void orr(CPU cpu, int op) {
    or(cpu, cpu.registers.getRegister(op & 0x7) & 0xFF);
  }

  static void orn(CPU cpu) {
    int n = cpu.nextUnsignedBytePC();

    or(cpu, n);
  }

  static void xorr(CPU cpu, int op) {
    cpu.registers.a =
        (cpu.registers.a ^ cpu.registers.getRegister(op & 0x7)) & 0xFF;
    cpu.registers.f = 0;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void andr(CPU cpu, int op) {
    cpu.registers.a =
        (cpu.registers.a & cpu.registers.getRegister(op & 0x7)) & 0xFF;
    cpu.registers.f = Registers.halfCarryFlag;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void adcr(CPU cpu, int op) {
    int carry = (cpu.registers.f & Registers.carryFlag) != 0 ? 1 : 0;
    int reg = cpu.registers.getRegister(op & 0x7) & 0xFF;
    int result = cpu.registers.a + reg + carry;

    cpu.registers.f = 0;
    if (((cpu.registers.a & 0xF) + (reg & 0xF) + carry) > 0xF) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    if (result > 0xFF) {
      cpu.registers.f |= Registers.carryFlag;
    }

    cpu.registers.a = result & 0xFF;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void add(CPU cpu, int n) {
    int result = cpu.registers.a + n;

    cpu.registers.f = 0;
    if (((cpu.registers.a & 0xF) + (n & 0xF)) > 0xF) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    if (result > 0xFF) {
      cpu.registers.f |= Registers.carryFlag;
    }

    cpu.registers.a = result & 0xFF;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void addr(CPU cpu, int op) {
    int n = cpu.registers.getRegister(op & 0x7) & 0xFF;
    add(cpu, n);
  }

  static void addn(CPU cpu) {
    int n = cpu.nextUnsignedBytePC();
    add(cpu, n);
  }

  static void sub(CPU cpu, int n) {
    cpu.registers.f = Registers.subtractFlag;
    if ((cpu.registers.a & 0xf) - (n & 0xf) < 0) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    cpu.registers.a -= n;
    if ((cpu.registers.a & MemoryAddresses.ioStart) != 0) {
      cpu.registers.f |= Registers.carryFlag;
    }

    cpu.registers.a &= 0xFF;
    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void subr(CPU cpu, int op) {
    int n = cpu.registers.getRegister(op & 0x7) & 0xFF;

    sub(cpu, n);
  }

  static void subn(CPU cpu) {
    int n = cpu.nextUnsignedBytePC();

    sub(cpu, n);
  }

  static void sbcn(CPU cpu) {
    int val = cpu.nextUnsignedBytePC();
    int carry = ((cpu.registers.f & Registers.carryFlag) != 0 ? 1 : 0);
    int n = val + carry;

    cpu.registers.f = Registers.subtractFlag;

    if ((cpu.registers.a & 0xf) - (val & 0xf) - carry < 0) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    cpu.registers.a -= n;

    if (cpu.registers.a < 0) {
      cpu.registers.f |= Registers.carryFlag;
      cpu.registers.a &= 0xFF;
    }

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void jphl(CPU cpu) {
    cpu.pc = cpu.registers.getRegisterPairSP(Registers.hl);
  }

  static void addhlrr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;
    int value = cpu.registers.getRegisterPairSP(pair);
    int hl = cpu.registers.getRegisterPairSP(Registers.hl);

    cpu.registers.f &= ~Registers.subtractFlag; // Reset N flag

    // Half-Carry check
    if (((hl & 0x0FFF) + (value & 0x0FFF)) > 0x0FFF) {
      cpu.registers.f |= Registers.halfCarryFlag;
    } else {
      cpu.registers.f &= ~Registers.halfCarryFlag;
    }

    // Carry check
    if ((hl + value) > 0xFFFF) {
      cpu.registers.f |= Registers.carryFlag;
    } else {
      cpu.registers.f &= ~Registers.carryFlag;
    }

    hl = (hl + value) & 0xFFFF;
    cpu.registers.setRegisterPairSP(Registers.hl, hl);
  }

  static void cp(CPU cpu, int n) {
    cpu.registers.f = Registers.subtractFlag;

    if (cpu.registers.a < n) {
      cpu.registers.f |= Registers.carryFlag;
    } else if (cpu.registers.a == n) {
      cpu.registers.f |= Registers.zeroFlag;
    }

    if ((cpu.registers.a & 0xF) < (n & 0xF)) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }
  }

  static void cpn(CPU cpu) {
    cp(cpu, cpu.nextUnsignedBytePC());
  }

  static void cprr(CPU cpu, int op) {
    cp(cpu, cpu.registers.getRegister(op & 0x7) & 0xFF);
  }

  static void incrr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;
    int o = cpu.registers.getRegisterPairSP(pair) & 0xFFFF;
    cpu.registers.setRegisterPairSP(pair, (o + 1) & 0xFFFF);
  }

  static void decr(CPU cpu, int op) {
    int reg = (op >> 3) & 0x7;
    int a = cpu.registers.getRegister(reg) & 0xFF;

    cpu.registers.f =
        (cpu.registers.f & Registers.carryFlag) | InstructionTables.dec[a];

    a = (a - 1) & 0xFF;

    cpu.registers.setRegister(reg, a);
  }

  static void incr(CPU cpu, int op) {
    int reg = (op >> 3) & 0x7;
    int a = cpu.registers.getRegister(reg) & 0xFF;

    cpu.registers.f =
        (cpu.registers.f & Registers.carryFlag) | InstructionTables.inc[a];

    a = (a + 1) & 0xFF;

    cpu.registers.setRegister(reg, a);
  }

  static void rlca(CPU cpu) {
    int a = cpu.registers.a;
    int carry = (a & 0x80) >> 7; // Check bit 7 (carry bit)

    // Rotate left and set carry
    a = ((a << 1) | carry) & 0xFF;

    // Update registers
    cpu.registers.a = a;
    cpu.registers.f = (carry != 0)
        ? Registers.carryFlag
        : 0; // Set carry flag if carry was set

    // Zero flag is not affected, so no need to modify it
  }

  static void jpnn(CPU cpu) {
    cpu.pc = (cpu.nextUnsignedBytePC()) | (cpu.nextUnsignedBytePC() << 8);
  }

  static void reti(CPU cpu) {
    cpu.pc = cpu.popWordSP(); // Pop return address
    cpu.interruptsEnabled = true; // Enable interrupts
  }

  static void lda16sp(CPU cpu) {
    int pos = ((cpu.nextUnsignedBytePC()) | (cpu.nextUnsignedBytePC() << 8));
    cpu.setByte(pos + 1, (cpu.sp & MemoryAddresses.ioStart) >> 8);
    cpu.setByte(pos, (cpu.sp & 0x00FF));
  }

  static void poprr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;
    int value = cpu.popWordSP();
    cpu.registers.setRegisterPair(pair, (value >> 8) & 0xFF, value & 0xFF);
  }

  static void pushrr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;
    int val = cpu.registers.getRegisterPair(pair);
    cpu.pushWordSP(val);
  }

  static void ldsphl(CPU cpu) {
    cpu.registers.setRegisterPairSP(
        Registers.sp, cpu.registers.getRegisterPairSP(Registers.hl));
  }
}

/// Instructions execution table used for faster execution of some instructions.
///
/// All possible values are pre calculated based on the instruction input.
class InstructionTables {
  /// for A in range(0x100):
  ///     F = F_N
  ///     if((A & 0xf) - 1 < 0): F |= F_H
  ///     if A - 1 == 0: F |= F_Z
  ///     DEC[A] = F
  static const List<int> dec = [
    96,
    192,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    96,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64,
    64
  ];

  /// for A in range(0x100):
  ///     F = 0
  ///     if((((A & 0xf) + 1) & 0xF0) != 0): F |= F_H
  ///     if(A + 1 > 0xFF): F |= F_Z
  ///     INC[A] = F
  static const List<int> inc = [
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    32,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    0,
    160
  ];
}
