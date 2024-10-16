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

  // Divider Register (Timer Divider)
  static const int div = 0x04;

  // Timer Counter (Incremented at the frequency specified by TAC)
  static const int tima = 0x05;

  // Timer Modulo (Value to which TIMA is reloaded upon overflow)
  static const int tma = 0x06;

  // Timer Control (Specifies clock input and timer enable)
  static const int tac = 0x07;

  // Work RAM bank register (Switches WRAM banks in GBC mode)
  static const int wramBank = 0x70;

  // VRAM bank register (Switches VRAM banks in GBC mode)
  static const int vramBank = 0x4f;

  // Sound registers

  // Channel 1: Sweep Register (controls frequency sweep for channel 1)
  static const int nr10 = 0x10;

  // Channel 1: Sound Length/Wave Duty Register (controls length and duty cycle of the waveform)
  static const int nr11 = 0x11;

  // Channel 1: Volume Envelope Register (controls volume envelope for channel 1)
  static const int nr12 = 0x12;

  // Channel 1: Frequency Low Register (lower 8 bits of frequency for channel 1)
  static const int nr13 = 0x13;

  // Channel 1: Frequency High/Control Register (upper 3 bits of frequency and control for starting/stopping sound)
  static const int nr14 = 0x14;

  // Channel 2: Sound Length/Wave Duty Register (controls length and duty cycle of the waveform)
  static const int nr21 = 0x16;

  // Channel 2: Volume Envelope Register (controls volume envelope for channel 2)
  static const int nr22 = 0x17;

  // Channel 2: Frequency Low Register (lower 8 bits of frequency for channel 2)
  static const int nr23 = 0x18;

  // Channel 2: Frequency High/Control Register (upper 3 bits of frequency and control for starting/stopping sound)
  static const int nr24 = 0x19;

  // Channel 3: Sound ON/OFF Register (enables/disables the wave output for channel 3)
  static const int nr30 = 0x1A;

  // Channel 3: Sound Length Register (length of the waveform)
  static const int nr31 = 0x1B;

  // Channel 3: Output Level Register (sets the volume for channel 3)
  static const int nr32 = 0x1C;

  // Channel 3: Frequency Low Register (lower 8 bits of frequency for channel 3)
  static const int nr33 = 0x1D;

  // Channel 3: Frequency High/Control Register (upper 3 bits of frequency and control for starting/stopping sound)
  static const int nr34 = 0x1E;

  // Channel 4: Sound Length Register (length of the noise sound)
  static const int nr41 = 0x20;

  // Channel 4: Volume Envelope Register (controls volume envelope for channel 4)
  static const int nr42 = 0x21;

  // Channel 4: Polynomial Counter Register (controls the characteristics of the noise)
  static const int nr43 = 0x22;

  // Channel 4: Control Register (controls start/stop and length of the noise sound)
  static const int nr44 = 0x23;

  // Output Control: Sound Panning Register (controls which channels are output to the left and right speakers)
  static const int nr51 = 0x25;

  // Sound ON/OFF and Status Register: Master control for enabling/disabling sound and indicating which channels are active
  static const int nr52 = 0x26;

  // Output Volume Register (controls left and right master volume for channels)
  static const int nr50 = 0x24;

  // The Tile Data Table address for the background can be selected via LCDC register.
  static const int lcdc = 0x40;

  // LCD Status Register: Provides details on the current status of the LCD controller
  static const int lcdStat = 0x41;

  // Scroll Y: Scrolls the background vertically
  static const int scy = 0x42;

  // Scroll X: Scrolls the background horizontally
  static const int scx = 0x43;

  // LY: The current scanline being rendered, values 0 to 153
  // 144 to 153 indicate V-Blank period
  static const int ly = 0x44;

  // LYC: LY Compare (generates an interrupt if LY matches LYC)
  static const int lyc = 0x45;

  // H-DMA control register contains the remaining length divided by 0x10 minus 1, a value of 0xFF indicates that the transfer is complete.
  static const int hdma = 0x55;

  // OAM DMA copy from ROM or RAM to OAM memory.
  static const int dma = 0x46;

  // Background Palette Register (used for Game Boy Color)
  static const int bgp = 0x47;

  // Object Palette 0 Data Register
  static const int obp0 = 0x48;

  // Object Palette 1 Data Register
  static const int obp1 = 0x49;

  // Interrupt flags register (IF): Tracks the interrupts that have been triggered
  static const int triggeredInterrupts = 0x0F;

  // Interrupt enable register (IE): Enables specific interrupts
  static const int enabledInterrupts = 0xFF;

  // Window Y position register: The Y position of the window (used for layering the window over the background)
  static const int wy = 0x4a;

  // Window X position register: The X position of the window
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
  // LCDC Bit 0: Background & Window Display Enable
  static const int lcdcBgWindowDisplayBit = 0x01;

  // LCDC Bit 1: Object Display Enable (sprites)
  static const int lcdcSpriteDisplayBit = 0x02;

  // LCDC Bit 2: Object Size (8x8 or 8x16)
  static const int lcdcSpriteSizeBit = 0x04;

  // LCDC Bit 3: Background Tile Map Display Select
  static const int lcdcBgTileMapDisplaySelectBit = 0x08;

  // LCDC Bit 4: Background & Window Tile Data Select
  static const int lcdcBgWindowTileDataSelectBit = 0x10;

  // LCDC Bit 5: Window Display Enable
  static const int lcdcWindowDisplayBit = 0x20;

  // LCDC Bit 6: Window Tile Map Display Select
  static const int lcdcWindowTileMapDisplaySelectBit = 0x40;

  // LCDC Bit 7: LCD Control Operation Enable
  static const int lcdcControlOperationBit = 0x80;

  // LCD Status Register (LCDSTAT) Bits
  // OAM Mode (Bit 5)
  static const int lcdStatOamModeBit = 0x20;

  // VBlank Mode (Bit 4)
  static const int lcdStatVBlankModeBit = 0x10;

  // HBlank Mode (Bit 3)
  static const int lcdStatHBlankModeBit = 0x08;

  // Coincidence Flag (Bit 2)
  static const int lcdStatCoincidenceBit = 0x04;

  // Coincidence Interrupt Enable (Bit 6)
  static const int lcdStatCoincidenceInterruptEnabledBit = 0x40;

  // LCDSTAT Mode Mask
  static const int lcdStatModeMask = 0x03;

  // LCDSTAT Mode 0: H-Blank
  static const int lcdStatModeHBlankBit = 0x0;

  // LCDSTAT Mode 1: V-Blank
  static const int lcdStatModeVBlankBit = 0x1;

  // LCDSTAT Mode 2: Searching OAM-RAM
  static const int lcdStatModeOamRamSearchBit = 0x2;

  // LCDSTAT Mode 3: Transferring Data to LCD Driver
  static const int lcdStatModeDataTransferBit = 0x3;
}
