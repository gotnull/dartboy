import 'package:dartboy/gui/button.dart';
import 'package:flutter/material.dart';

class RomItem {
  final String? romPath;
  final String displayName;
  final List<RomItem>? subItems;

  RomItem({
    required this.displayName,
    this.romPath,
    this.subItems,
  });

  bool get isFolder => subItems != null && subItems!.isNotEmpty;
}

class PopupSubMenuItem<T> extends PopupMenuEntry<T> {
  const PopupSubMenuItem({
    super.key,
    required this.title,
    required this.items,
    this.onSelected,
  });

  final String title;
  final List<RomItem> items;
  final Function(RomItem)? onSelected;

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(T? value) => false;

  @override
  State createState() => _PopupSubMenuState();
}

class _PopupSubMenuState extends State<PopupSubMenuItem> {
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RomItem>(
      tooltip: "",
      color: Colors.blue, // Uniform background color for popup
      onSelected: (RomItem value) {
        widget.onSelected?.call(value);
        Navigator.pop(context); // Close the parent menu
      },
      itemBuilder: (BuildContext context) {
        return widget.items.map<PopupMenuEntry<RomItem>>(
          (RomItem item) {
            if (item.isFolder) {
              return PopupSubMenuItem<RomItem>(
                title: item.displayName,
                items: item.subItems!,
                onSelected: widget.onSelected,
              );
            } else {
              return PopupMenuItem<RomItem>(
                value: item,
                child: Text(
                  item.displayName,
                  style: proggyTextStyle(), // White text
                ),
              );
            }
          },
        ).toList();
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Text(
                widget.title,
                style: proggyTextStyle(),
              ),
            ),
            const Icon(Icons.arrow_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class MyRomMenu extends StatefulWidget {
  final void Function(String?) onRomSelected;

  const MyRomMenu({super.key, required this.onRomSelected});

  @override
  MyRomMenuState createState() => MyRomMenuState();
}

class MyRomMenuState extends State<MyRomMenu> {
  String selectedRomName = "Select ROM"; // Initial text

  List<RomItem> romMap = [
    RomItem(
      displayName: "Blargg's Test",
      subItems: [
        RomItem(
          displayName: "cpu_instrs",
          romPath: "assets/roms/blargg/cpu_instrs/cpu_instrs.gb",
        ),
        RomItem(
          displayName: "cgb_sound",
          romPath: "assets/roms/blargg/cgb_sound.gb",
        ),
        RomItem(
          displayName: "dmg_sound",
          romPath: "assets/roms/blargg/dmg_sound.gb",
        ),
        RomItem(
          displayName: "instr_timing",
          subItems: [
            RomItem(
              displayName: "instr_timing",
              romPath: "assets/roms/blargg/instr_timing/instr_timing.gb",
            ),
          ],
        ),
        RomItem(
          displayName: "halt_bug",
          romPath: "assets/roms/blargg/halt_bug.gb",
        ),
        RomItem(
          displayName: "interrupt_time",
          romPath: "assets/roms/blargg/interrupt_time.gb",
        ),
        RomItem(
          displayName: "mem_timing",
          romPath: "assets/roms/blargg/mem_timing.gb",
        ),
        RomItem(
          displayName: "oam_bug",
          romPath: "assets/roms/blargg/oam_bug.gb",
        ),
      ],
    ),
    RomItem(
      displayName: "Mooneye Test",
      subItems: [
        RomItem(
          displayName: "basic.gb",
          romPath: "assets/roms/mooneye/oam_dma/basic.gb",
        ),
        RomItem(
          displayName: "reg_read.gb",
          romPath: "assets/roms/mooneye/oam_dma/reg_read.gb",
        ),
      ],
    ),
    RomItem(
      displayName: "Games",
      subItems: [
        RomItem(
          displayName: "Robocop",
          romPath: "assets/roms/Robocop (U) (M6) [C][!].gbc",
        ),
        RomItem(
          displayName: "Rod Land",
          romPath: "assets/roms/Rodland (Europe).gb",
        ),
        RomItem(
          displayName: "Metal Gear Solid",
          romPath: "assets/roms/Metal Gear Solid (USA).gbc",
        ),
        RomItem(
          displayName: "Zelda: Oracle of Seasons",
          romPath: "assets/roms/zelda.gbc",
        ),
        RomItem(
          displayName: "Zelda: Link's Awakening",
          romPath: "assets/roms/legend_of_zelda_links_awakening.gbc",
        ),
        RomItem(
          displayName: "Super Mario Bros. Deluxe",
          romPath: "assets/roms/smb_deluxe.gbc",
        ),
        RomItem(
          displayName: "Donkey Kong Country",
          romPath: "assets/roms/donkey_kong_country.gbc",
        ),
        RomItem(
          displayName: "Dr. Mario World",
          romPath: "assets/roms/dr_mario_world.gb",
        ),
        RomItem(
          displayName: "Dragon Warrior Monsters",
          romPath: "assets/roms/dragon_warrior_monsters.gbc",
        ),
        RomItem(
          displayName: "Dr. Mario",
          romPath: "assets/roms/drmario.gb",
        ),
        RomItem(
          displayName: "Kirby's Dreamland",
          romPath: "assets/roms/kirbys_dreamland.gb",
        ),
        RomItem(
          displayName: "Opus5",
          romPath: "assets/roms/opus5.gb",
        ),
        RomItem(
          displayName: "Pokemon Gold",
          romPath: "assets/roms/pokemon_gold.gbc",
        ),
        RomItem(
          displayName: "Pokemon Yellow",
          romPath: "assets/roms/pokemon_yellow.gbc",
        ),
        RomItem(
          displayName: "Tetris World DX",
          romPath: "assets/roms/tetris_world_dx.gbc",
        ),
        RomItem(
          displayName: "Tetris",
          romPath: "assets/roms/tetris.gb",
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<RomItem>(
      tooltip: "", // Disable tooltip
      color: Colors.blue, // Background color of the menu and submenu
      offset: const Offset(0, 40), // Adjust offset for better positioning
      onSelected: (RomItem selectedRom) {
        setState(() {
          selectedRomName = selectedRom.displayName; // Update the button text
        });
        widget.onRomSelected(selectedRom.romPath);
      },
      itemBuilder: (BuildContext context) {
        return romMap.map<PopupMenuEntry<RomItem>>(
          (RomItem item) {
            if (item.isFolder) {
              return PopupSubMenuItem<RomItem>(
                title: item.displayName,
                items: item.subItems!,
                onSelected: (RomItem selectedSubRom) {
                  widget.onRomSelected(
                    selectedSubRom.romPath,
                  ); // Pass subfolder ROM selection to callback
                },
              );
            } else {
              return PopupMenuItem<RomItem>(
                value: item,
                child: Text(
                  item.displayName,
                  style: proggyTextStyle(),
                ),
              );
            }
          },
        ).toList();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 8,
        ),
        decoration: const BoxDecoration(
          color: Colors.blue, // Background color of the button
        ),
        child: Row(
          children: [
            Text(
              selectedRomName,
              style: proggyTextStyle(), // White text for visibility
            ),
            const Icon(
              Icons.arrow_drop_down,
              color: Colors.white, // White arrow for visibility
            ),
          ],
        ),
      ),
    );
  }
}
