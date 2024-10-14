import 'mbc.dart';

class MBC2 extends MBC {
  MBC2(super.cpu);

  @override
  void writeByte(int address, int value) {
    address &= 0xFFFF;
    super.writeByte(address, value);
  }
}
