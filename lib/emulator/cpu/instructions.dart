import 'package:dartboy/emulator/cpu/cpu.dart';
import 'package:dartboy/emulator/cpu/registers.dart';
import 'package:dartboy/utils/console.dart';

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

  static void NOP(CPU cpu) {
    //addDebugStack('NOP', cpu);
  }

  static void CALL_cc_nn(CPU cpu, int op) {
    int addr = (cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8));
    if (cpu.registers.getFlag(0x4 | ((op >> 3) & 0x7))) {
      cpu.pushWordSP(cpu.pc); // Save current PC
      cpu.pc = addr; // Jump to new address
      cpu.tick(4);
    }
  }

  static void CALL_nn(CPU cpu) {
    int jmp = (cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8));
    cpu.pushWordSP(cpu.pc); // Push the current PC to the stack
    cpu.pc = jmp;
    cpu.tick(4); // Ensure that the correct number of cycles is added here
  }

  static void LD_dd_nn(CPU cpu, int op) {
    //addDebugStack('LD_dd_nn', cpu);

    cpu.registers.setRegisterPairSP((op >> 4) & 0x3,
        cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8));
  }

  static void LD_r_n(CPU cpu, int op) {
    //addDebugStack('LD_r_n', cpu);

    int to = (op >> 3) & 0x7;
    int n = cpu.nextUnsignedBytePC();
    cpu.registers.setRegister(to, n);
  }

  static void LD_A_BC(CPU cpu) {
    //addDebugStack('LD_A_BC', cpu);

    cpu.registers.a =
        cpu.getUnsignedByte(cpu.registers.getRegisterPairSP(Registers.bc));
  }

  static void LD_A_DE(CPU cpu) {
    //addDebugStack('LD_A_DE', cpu);

    cpu.registers.a =
        cpu.getUnsignedByte(cpu.registers.getRegisterPairSP(Registers.de));
  }

  static void LD_BC_A(CPU cpu) {
    //addDebugStack('LD_BC_A', cpu);

    cpu.mmu.writeByte(
        cpu.registers.getRegisterPairSP(Registers.bc), cpu.registers.a);
  }

  static void LD_DE_A(CPU cpu) {
    //addDebugStack('LD_DE_A', cpu);

    cpu.mmu.writeByte(
        cpu.registers.getRegisterPairSP(Registers.de), cpu.registers.a);
  }

  static void LD_A_C(CPU cpu) {
    cpu.registers.a = cpu.mmu.readByte(0xFF00 | cpu.registers.c);
  }

  static void ADD_SP_n(CPU cpu) {
    //addDebugStack('ADD_SP_n', cpu);

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
    cpu.tick(4);
  }

  static void SCF(CPU cpu) {
    cpu.registers.f &= Registers.zeroFlag; // Keep zero flag unchanged
    cpu.registers.f |= Registers.carryFlag; // Set carry flag
    cpu.registers.f &= ~Registers.subtractFlag; // Clear subtract flag
    cpu.registers.f &= ~Registers.halfCarryFlag; // Clear half-carry flag
  }

  static void CCF(CPU cpu) {
    //addDebugStack('CCF', cpu);

    cpu.registers.f = (cpu.registers.f & Registers.carryFlag) != 0
        ? (cpu.registers.f & Registers.zeroFlag)
        : ((cpu.registers.f & Registers.zeroFlag) | Registers.carryFlag);
  }

  static void LD_A_n(CPU cpu) {
    cpu.registers.a = cpu.getUnsignedByte(
        cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) - 1) & 0xFFFF);
  }

  static void LD_nn_A(CPU cpu) {
    int address = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    cpu.mmu.writeByte(address, cpu.registers.a);
  }

  static void LDHL_SP_n(CPU cpu) {
    //addDebugStack('LDHL_SP_n', cpu);

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

  static void CPL(CPU cpu) {
    //addDebugStack('CPL', cpu);

    cpu.registers.a = (~cpu.registers.a) & 0xFF;
    cpu.registers.f =
        (cpu.registers.f & (Registers.carryFlag | Registers.zeroFlag)) |
            Registers.halfCarryFlag |
            Registers.subtractFlag;
  }

  static void LD_FFn_A(CPU cpu) {
    //addDebugStack('LD_FFn_A', cpu);

    cpu.mmu.writeByte(0xFF00 | cpu.nextUnsignedBytePC(), cpu.registers.a);
  }

  static void LDH_FFC_A(CPU cpu) {
    //addDebugStack('LDH_FFC_A', cpu);

    cpu.mmu.writeByte(0xFF00 | (cpu.registers.c & 0xFF), cpu.registers.a);
  }

  static void LD_A_nn(CPU cpu) {
    //addDebugStack('LD_A_nn', cpu);

    int nn = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    cpu.registers.a = cpu.getUnsignedByte(nn);
  }

  static void LD_A_HLI(CPU cpu) {
    //addDebugStack('LD_A_HLI', cpu);

    cpu.registers.a = cpu.getUnsignedByte(
        cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) + 1) & 0xFFFF);
  }

  static void LD_HLI_A(CPU cpu) {
    //addDebugStack('LD_HLI_A', cpu);

    cpu.mmu.writeByte(cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF,
        cpu.registers.a);
    cpu.registers.setRegisterPairSP(Registers.hl,
        (cpu.registers.getRegisterPairSP(Registers.hl) + 1) & 0xFFFF);
  }

  static void LD_HLD_A(CPU cpu) {
    //addDebugStack('LD_HLD_A', cpu);

    int hl = cpu.registers.getRegisterPairSP(Registers.hl);
    cpu.mmu.writeByte(hl, cpu.registers.a);

    cpu.registers.setRegisterPairSP(Registers.hl, (hl - 1) & 0xFFFF);
  }

  static void STOP(CPU cpu) {
    //addDebugStack('STOP', cpu);

    NOP(cpu);
  }

  static void LD_r_r(CPU cpu, int op) {
    int from = op & 0x7;
    int to = (op >> 3) & 0x7;

    if (from == 6) {
      // Handle LD r, (HL)
      int hl = cpu.registers.getRegisterPairSP(Registers.hl);
      int value = cpu.mmu.readByte(hl);
      cpu.registers.setRegister(to, value);
    } else if (to == 6) {
      // Handle LD (HL), r
      int hl = cpu.registers.getRegisterPairSP(Registers.hl);
      int value = cpu.registers.getRegister(from);
      cpu.mmu.writeByte(hl, value);
    } else {
      // Handle LD r, r
      int value = cpu.registers.getRegister(from);
      cpu.registers.setRegister(to, value);
    }
  }

  static void CBPrefix(CPU cpu) {
    //addDebugStack('CBPrefix', cpu);

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
  }

  static void DEC_rr(CPU cpu, int op) {
    //addDebugStack('DEC_rr', cpu);

    int pair = (op >> 4) & 0x3;
    int o = cpu.registers.getRegisterPairSP(pair);
    cpu.registers.setRegisterPairSP(pair, o - 1);
  }

  static void RLA(CPU cpu) {
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

  static void RRA(CPU cpu) {
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

  static void RRCA(CPU cpu) {
    bool carry = (cpu.registers.a & 0x01) != 0; // Check bit 0 for carry
    cpu.registers.a = ((cpu.registers.a >> 1) | (carry ? 0x80 : 0)) &
        0xFF; // Rotate right circular

    cpu.registers.f = 0; // Clear all flags
    if (carry) {
      cpu.registers.f |= Registers.carryFlag; // Set carry flag if bit 0 was set
    }
  }

  static void SBC_r(CPU cpu, int op) {
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

  static void ADC_n(CPU cpu) {
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

  static void RET(CPU cpu) {
    int lo = cpu.getUnsignedByte(cpu.sp); // Fetch lower byte from stack
    int hi = cpu.getUnsignedByte(cpu.sp + 1); // Fetch upper byte from stack
    cpu.sp += 2; // Increment stack pointer
    cpu.pc = (hi << 8) | lo; // Set PC to the value retrieved from stack
    cpu.tick(4); // Add extra cycles
  }

  static void XOR_n(CPU cpu) {
    int value = cpu.nextUnsignedBytePC(); // Fetch immediate value
    cpu.registers.a ^= value; // XOR A with immediate value
    cpu.registers.f = 0; // Reset flags

    if (cpu.registers.a == 0) {
      // Set zero flag if result is 0
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void AND_n(CPU cpu) {
    int value = cpu.nextUnsignedBytePC(); // Fetch immediate value
    cpu.registers.a &= value; // AND A with immediate value
    cpu.registers.f = Registers.halfCarryFlag; // Always set the half-carry flag

    if (cpu.registers.a == 0) {
      // Set zero flag if result is 0
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void EI(CPU cpu) {
    cpu.enableInterruptsNextCycle =
        true; // Enable interrupts after the next instruction
    cpu.tick(4); // Delay for 4 cycles
  }

  static void DI(CPU cpu) {
    cpu.interruptsEnabled = false;
    // Just disabling interrupts, no delay needed
  }

  static void RST_p(CPU cpu, int op) {
    cpu.pushWordSP(cpu.pc); // Save current PC on the stack
    cpu.pc = op & 0x38; // Jump to the specific reset vector
    cpu.tick(4);
  }

  static void RET_c(CPU cpu, int op) {
    //addDebugStack('RET_c', cpu);

    if (cpu.registers.getFlag(0x4 | ((op >> 3) & 0x7))) {
      cpu.pc =
          (cpu.getUnsignedByte(cpu.sp + 1) << 8) | cpu.getUnsignedByte(cpu.sp);
      cpu.sp += 2;
    }

    cpu.tick(4);
  }

  static void HALT(CPU cpu) {
    if (!cpu.interruptsEnabled) {
      // Halt bug: The PC doesn't increase, and the CPU stays in HALT state until an interrupt occurs.
      cpu.halted = true;
    } else {
      cpu.halted = true;
    }
  }

  static void LDH_FFnn(CPU cpu) {
    //addDebugStack('LDH_FFnn', cpu);

    cpu.registers.a = cpu.getUnsignedByte(0xFF00 | cpu.nextUnsignedBytePC());
  }

  static void JR_c_e(CPU cpu, int op) {
    //addDebugStack('JR_c_e', cpu);

    int e = cpu.nextSignedBytePC();

    if (cpu.registers.getFlag((op >> 3) & 0x7)) {
      cpu.pc += e;
      cpu.tick(4);
    }
  }

  static void JP_c_nn(CPU cpu, int op) {
    int addr = cpu.nextUnsignedBytePC() | (cpu.nextUnsignedBytePC() << 8);
    if (cpu.registers.getFlag(0x4 | ((op >> 3) & 0x7))) {
      cpu.pc = addr; // Jump to new address
      cpu.tick(4);
    }
  }

  static void DAA(CPU cpu) {
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

  static void JR_e(CPU cpu) {
    //addDebugStack('JR_e', cpu);

    int e = cpu.nextSignedBytePC();
    cpu.pc += e;
    cpu.tick(4);
  }

  static void OR(CPU cpu, int n) {
    //addDebugStack('OR', cpu);

    cpu.registers.a |= n;
    cpu.registers.f = 0;
    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void OR_r(CPU cpu, int op) {
    //addDebugStack('OR_r', cpu);

    OR(cpu, cpu.registers.getRegister(op & 0x7) & 0xFF);
  }

  static void OR_n(CPU cpu) {
    //addDebugStack('OR_n', cpu);

    int n = cpu.nextUnsignedBytePC();

    OR(cpu, n);
  }

  static void XOR_r(CPU cpu, int op) {
    //addDebugStack('XOR_r', cpu);

    cpu.registers.a =
        (cpu.registers.a ^ cpu.registers.getRegister(op & 0x7)) & 0xFF;
    cpu.registers.f = 0;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void AND_r(CPU cpu, int op) {
    //addDebugStack('AND_r', cpu);

    cpu.registers.a =
        (cpu.registers.a & cpu.registers.getRegister(op & 0x7)) & 0xFF;
    cpu.registers.f = Registers.halfCarryFlag;

    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void ADC_r(CPU cpu, int op) {
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

  static void ADD(CPU cpu, int n) {
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

  static void ADD_r(CPU cpu, int op) {
    //addDebugStack('ADD_r', cpu);

    int n = cpu.registers.getRegister(op & 0x7) & 0xFF;
    ADD(cpu, n);
  }

  static void ADD_n(CPU cpu) {
    //addDebugStack('ADD_n', cpu);

    int n = cpu.nextUnsignedBytePC();
    ADD(cpu, n);
  }

  static void SUB(CPU cpu, int n) {
    //addDebugStack('SUB', cpu);

    cpu.registers.f = Registers.subtractFlag;
    if ((cpu.registers.a & 0xf) - (n & 0xf) < 0) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    cpu.registers.a -= n;
    if ((cpu.registers.a & 0xFF00) != 0) {
      cpu.registers.f |= Registers.carryFlag;
    }

    cpu.registers.a &= 0xFF;
    if (cpu.registers.a == 0) {
      cpu.registers.f |= Registers.zeroFlag;
    }
  }

  static void SUB_r(CPU cpu, int op) {
    //addDebugStack('SUB_r', cpu);

    int n = cpu.registers.getRegister(op & 0x7) & 0xFF;

    SUB(cpu, n);
  }

  static void SUB_n(CPU cpu) {
    //addDebugStack('SUB_n', cpu);

    int n = cpu.nextUnsignedBytePC();

    SUB(cpu, n);
  }

  static void SBC_n(CPU cpu) {
    //addDebugStack('SBC_n', cpu);

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

  static void JP_HL(CPU cpu) {
    //addDebugStack('JP_HL', cpu);

    cpu.pc = cpu.registers.getRegisterPairSP(Registers.hl) & 0xFFFF;
  }

  static void ADD_HL_rr(CPU cpu, int op) {
    //addDebugStack('ADD_HL_rr', cpu);

    // Z is not affected is set if carry out of bit 11; reset otherwise
    // N is reset is set if carry from bit 15; reset otherwise
    int pair = (op >> 4) & 0x3;
    int ss = cpu.registers.getRegisterPairSP(pair);
    int hl = cpu.registers.getRegisterPairSP(Registers.hl);

    cpu.registers.f &= Registers.zeroFlag;

    if (((hl & 0xFFF) + (ss & 0xFFF)) > 0xFFF) {
      cpu.registers.f |= Registers.halfCarryFlag;
    }

    hl += ss;

    if (hl > 0xFFFF) {
      cpu.registers.f |= Registers.carryFlag;
      hl &= 0xFFFF;
    }

    cpu.registers.setRegisterPairSP(Registers.hl, hl);
  }

  static void CP(CPU cpu, int n) {
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

  static void CP_n(CPU cpu) {
    //addDebugStack('CP_n', cpu);

    CP(cpu, cpu.nextUnsignedBytePC());
  }

  static void CP_rr(CPU cpu, int op) {
    //addDebugStack('CP_rr', cpu);

    CP(cpu, cpu.registers.getRegister(op & 0x7) & 0xFF);
  }

  static void INC_rr(CPU cpu, int op) {
    //addDebugStack('INC_rr', cpu);

    int pair = (op >> 4) & 0x3;
    int o = cpu.registers.getRegisterPairSP(pair) & 0xFFFF;
    cpu.registers.setRegisterPairSP(pair, o + 1);
  }

  static void DEC_r(CPU cpu, int op) {
    //addDebugStack('DEC_r', cpu);

    int reg = (op >> 3) & 0x7;
    int a = cpu.registers.getRegister(reg) & 0xFF;

    cpu.registers.f =
        (cpu.registers.f & Registers.carryFlag) | InstructionTables.DEC[a];

    a = (a - 1) & 0xFF;

    cpu.registers.setRegister(reg, a);
  }

  static void INC_r(CPU cpu, int op) {
    //addDebugStack('INC_r', cpu);

    int reg = (op >> 3) & 0x7;
    int a = cpu.registers.getRegister(reg) & 0xFF;

    cpu.registers.f =
        (cpu.registers.f & Registers.carryFlag) | InstructionTables.INC[a];

    a = (a + 1) & 0xFF;

    cpu.registers.setRegister(reg, a);
  }

  static void RLCA(CPU cpu) {
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

  static void JP_nn(CPU cpu) {
    //addDebugStack('JP_nn', cpu);

    cpu.pc = (cpu.nextUnsignedBytePC()) | (cpu.nextUnsignedBytePC() << 8);
    cpu.tick(4);
  }

  static void RETI(CPU cpu) {
    //addDebugStack('RETI', cpu);

    cpu.interruptsEnabled = true;
    cpu.pc =
        (cpu.getUnsignedByte(cpu.sp + 1) << 8) | cpu.getUnsignedByte(cpu.sp);
    cpu.sp += 2;
    cpu.tick(4);
  }

  static void LD_a16_SP(CPU cpu) {
    //addDebugStack('LD_a16_SP', cpu);

    int pos = ((cpu.nextUnsignedBytePC()) | (cpu.nextUnsignedBytePC() << 8));
    cpu.mmu.writeByte(pos + 1, (cpu.sp & 0xFF00) >> 8);
    cpu.mmu.writeByte(pos, (cpu.sp & 0x00FF));
  }

  static void POP_rr(CPU cpu, int op) {
    int pair = (op >> 4) & 0x3;

    int lo = cpu.popByteSP();
    int hi = cpu.popByteSP();
    cpu.registers.setRegisterPair(pair, hi, lo);
  }

  static void PUSH_rr(CPU cpu, int op) {
    // Get the register pair
    int pair = (op >> 4) & 0x3;

    // Fetch the value from the register pair
    int val = cpu.registers.getRegisterPair(pair);

    // Push the higher byte first, then the lower byte onto the stack
    cpu.pushWordSP(val);
    cpu.tick(4); // Extra cycles for PUSH
  }

  static void LD_SP_HL(CPU cpu) {
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
  static const List<int> DEC = [
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
  static const List<int> INC = [
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
