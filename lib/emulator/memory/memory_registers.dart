class MemoryRegisters {
  // Used to control the double speed mode (gameboy color only).
  static const int doubleSpeed = 0x4d;

  // Gamepad I/O register, stores which keys are pressed by the user.
  static const int gamepad = 0x00;

  // Stores the data transferred by serial cable
  static const int serialSb = 0x01;

  // Serial data control register, (data connection control, clock speed, etc).
  static const int serialSc = 0x02;

  // Background palette (gameboy color only)
  static const int backgroundPaletteIndex = 0x68;
  static const int backgroundPaletteData = 0x69;

  // Sprite palette (gameboy color only)
  static const int spritePaletteIndex = 0x6A;
  static const int spritePaletteData = 0x6B;

  static const int div = 0x04;
  static const int tima = 0x05;
  static const int tma = 0x06;
  static const int tac = 0x07;
  static const int wramBank = 0x70;
  static const int vramBank = 0x4f;

  // Sound registers
  static const int nr10 = 0x10;
  static const int nr11 = 0x11;
  static const int nr12 = 0x12;
  static const int nr13 = 0x13;
  static const int nr14 = 0x14;
  static const int nr21 = 0x16;
  static const int nr22 = 0x17;
  static const int nr23 = 0x18;
  static const int nr24 = 0x19;
  static const int nr30 = 0x1A;
  static const int nr31 = 0x1B;
  static const int nr32 = 0x1C;
  static const int nr33 = 0x1D;
  static const int nr34 = 0x1E;
  static const int nr41 = 0x20;
  static const int nr42 = 0x21;
  static const int nr43 = 0x22;
  static const int nr44 = 0x23;
  static const int nr51 = 0x25;
  static const int nr52 = 0x26;

  // The Tile Data Table address for the background can be selected via LCDC register.
  static const int lcdc = 0x40;
  static const int lcdStat = 0x41;
  static const int scy = 0x42;
  static const int scx = 0x43;

  // The LY indicates the vertical line to which the present data is transferred to the LCD Driver.
  // Has value between 0 to 153. The values between 144 and 153 indicate the V-Blank period.
  static const int ly = 0x44;

  static const int lyc = 0x45;

  // H-DMA control register contains the remaining length divided by 0x10 minus 1, a value of 0FFH indicates that the transfer is complete.
  static const int hdma = 0x55;

  // OAM DMA copy from ROM or RAM to OAM memory.
  static const int dma = 0x46;

  // This register allows to read/write data to the CGBs Background Palette Memory, addressed through Register FF68.
  static const int bgp = 0x47;

  static const int obp0 = 0x48;
  static const int obp1 = 0x49;
  static const int triggeredInterrupts = 0x0F; // IF
  static const int enabledInterrupts = 0xFF;
  static const int wy = 0x4a;
  static const int wx = 0x4b;

  // Masks for TRIGGERED_INTERRUPTS and ENABLED_INTERRUPTS.
  static const int vblankBit = 0x1;
  static const int lcdcBit = 0x2;
  static const int timerOverflowBit = 0x4;
  static const int serialTransferBit = 0x8;
  static const int hiloBit = 0x10;

  // The addresses to jump to when an interrupt is triggered.
  static const int vblankHandlerAddress = 0x40;
  static const int lcdcHandlerAddress = 0x48;
  static const int timerOverflowHandlerAddress = 0x50;
  static const int serialTransferHandlerAddress = 0x58;
  static const int hiloHandlerAddress = 0x60;

  // LCD Related values
  static const int lcdcBgWindowDisplayBit = 0x01;
  static const int lcdcSpriteDisplayBit = 0x02;
  static const int lcdcSpriteSizeBit = 0x04;
  static const int lcdcBgTileMapDisplaySelectBit = 0x08;
  static const int lcdcBgWindowTileDataSelectBit = 0x10;
  static const int lcdcWindowDisplayBit = 0x20;
  static const int lcdcWindowTileMapDisplaySelectBit = 0x40;
  static const int lcdcControlOperationBit = 0x80;

  static const int lcdStatOamModeBit = 0x20;
  static const int lcdStatVBlankModeBit = 0x10;
  static const int lcdStatHBlankModeBit = 0x8;
  static const int lcdStatCoincidenceBit = 0x4;
  static const int lcdStatCoincidenceInterruptEnabledBit = 0x40;
  static const int lcdStatModeMask = 0x3;

  static const int lcdStatModeHBlankBit = 0x0;
  static const int lcdStatModeVBlankBit = 0x1;
  static const int lcdStatModeOamRamSearchBit = 0x2;
  static const int lcdStatModeDataTransferBit = 0x3;
}
