import 'package:dartboy/emulator/memory/memory.dart';
import 'package:dartboy/emulator/memory/memory_registers.dart';

/// Represents a H-Blank DMA (direct memory access) transfer session.
///
/// DMA transfers 16 bytes from source to dest every H-Blank interval, and can be used for a lot of video effects.
class DMA {
  /// Memory for the DMA (memory of the system).
  Memory? memory;

  /// The source address.
  int source = 0;

  /// The destination address.
  int destination = 0;

  /// The length of the transfer, is reduced on each tick.
  int length = 0;

  /// The current offset into the source/destination buffers.
  int position = 0;

  /// Creates a new DMA instance.
  ///
  /// @param source The source address to copy from.
  /// @param dest The destination address to copy to.
  /// @param length How many bytes to copy.
  DMA(this.memory, this.source, this.destination, this.length);

  /// DMA transfers 0x10 bytes of data during each H-Blank, ie. at LY=0-143, no data is transferred during V-Blank (LY=144-153), but the transfer will then continue at LY=00.
  ///
  /// The execution of the program is halted during the separate transfers, but the program execution continues during the 'spaces' between each data block.
  ///
  /// Note that the program may not change the Destination VRAM bank (0xFF4F), or the Source ROM/RAM bank (in case data is transferred from bankable memory) until the transfer has completed!
  ///
  /// Reading from Register 0xFF55 returns the remaining length (divided by 10h, minus 1), a value of 0FFh ndicates that the transfer has completed.
  ///
  /// It is also possible to terminate an active H-Blank transfer by writing zero to Bit 7 of 0xFF55.
  ///
  /// In that case reading from 0xFF55 may return any value for the lower 7 bits, but Bit 7 will be read as 1.
  void tick() {
    for (int i = 0; i < 0x10; i++) {
      memory!.vram[memory!.vramPageStart + destination + position + i] =
          memory!.readByte(source + i) & 0xFF;
    }

    position += 0x10;
    length -= 0x10;

    if (length == 0) {
      memory!.dma = null;
      memory!.registers[MemoryRegisters.hdma] = 0xff;
      memory = null;
      // print("Finished DMA from " + source.toString() + " to " + destination.toString());
    } else {
      memory!.registers[MemoryRegisters.hdma] = (length ~/ 0x10 - 1);
    }
  }
}
