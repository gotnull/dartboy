/// Stored the address layout of the gameboy in constants.
///
/// Interrupt Enable Register FF80 - FFFF
/// Internal RAM FF4C - FF80
/// Empty but unusable for I/O FF4C - FF80
/// I/O ports FEA0 - FF00 - FF4C
/// Empty but unusable for I/O FEA0 - FF00
/// Sprite attribute Memory (OAM) FE00 - FEA0
/// Echo of 8kB Internal RAM E000 - FE00 (E000-FE00 appear to access the internal RAM the same as C000-DE00)
/// 8kB Internal RAM C000 - E000
/// 8kB switchable RAM bank A000 - C000
/// 8kB Video RAM 8000 - A000
/// 16kB switchable ROM bank 4000 - 8000 (32kB Cartridge)
/// 16kB ROM bank #0 0000 - 4000
class MemoryAddresses {
  /// Total memory addressable size
  static const addressSize = 65536;

  /// Size of a page of Video RAM, in bytes. 8kb.
  static const int vramPageSize = 0x2000;

  /// Size of a page of Work RAM, in bytes. 4kb.
  static const int wramPageSize = 0x1000;

  /// Size of a page of ROM, in bytes. 16kb.
  static const int romPageSize = 0x4000;

  // 32KB Cartridge ROM
  static const cartridgeRomStart = 0x0000;
  static const cartridgeRomSwitchableStart = 0x4000;
  static const cartridgeRomEnd = 0x8000;

  // Video RAM
  static const videoRamStart = 0x8000;
  static const videoRamEnd = 0xA000;

  // 8KB Switchable RAM (Cartridge)
  static const switchableRamStart = 0xA000;
  static const switchableRamEnd = 0xC000;

  // 8KB Internal RAM A
  static const ramAstart = 0xC000;
  static const ramASwitchableStart = 0xD000;
  static const ramAEnd = 0xE000;

  // 8KB RAM A echo
  static const ramAEchoStart = 0xE000;
  static const ramAEchoEnd = 0xFE00;

  // Sprite attribute
  static const oamStart = 0xFE00;
  static const oamEnd = 0xFEA0;

  // Empty zone A
  static const emptyAStart = 0xFEA0;
  static const emptyAEnd = 0xFF00;

  // IO ports
  static const ioStart = 0xFF00;
  static const ioEnd = 0xFF4C;

  // Empty zone B
  static const emptyBStart = 0xFF4C;
  static const emptyBEnd = 0xFF80;

  // Internal RAM B (Registers)
  static const ramBStart = 0xFF80;
  static const ramBEnd = 0xFFFF;

  // Interrupt enable register
  static const interruptEnableRegister = 0xFFFF;
}
