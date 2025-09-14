import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dartboy/emulator/memory/cartridge.dart';

class RomInfo {
  final String name;
  final String path;
  final String platform;
  final bool isTestRom;
  final String fileName;

  RomInfo({
    required this.name,
    required this.path,
    required this.platform,
    required this.fileName,
    this.isTestRom = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'path': path,
    'platform': platform,
    'fileName': fileName,
    'isTestRom': isTestRom,
  };

  factory RomInfo.fromJson(Map<String, dynamic> json) => RomInfo(
    name: json['name'],
    path: json['path'],
    platform: json['platform'],
    fileName: json['fileName'],
    isTestRom: json['isTestRom'] ?? false,
  );
}

class RomManager {
  static const String _cacheKey = 'rom_cache';
  static const String _versionKey = 'rom_cache_version';
  static const String _manifestKey = 'rom_manifest_hash';
  static const String _currentVersion = '3.2'; // Updated to force cache refresh

  static Future<List<RomInfo>> getAvailableRoms() async {
    try {
      // Always rescan on first load - load the ROM manifest
      final manifestData = await rootBundle.loadString('assets/rom_manifest.json');
      final manifest = json.decode(manifestData) as Map<String, dynamic>;

      print('Rescanning ROMs using emulator cartridge system...');

      // Always scan for ROMs using the manifest and emulator
      final roms = await _scanForRomsFromManifest(manifest);

      // Cache is optional - try to cache but don't fail if it doesn't work
      try {
        final manifestHash = manifestData.hashCode.toString();
        await _cacheRoms(roms, manifestHash);
      } catch (e) {
        print('Could not cache ROMs: $e');
      }

      return roms;
    } catch (e) {
      print('Error loading ROM manifest: $e');
      return [];
    }
  }

  static String _cleanCartridgeName(String rawName) {
    // First, find the first null character and truncate there
    int nullIndex = rawName.indexOf('\x00');
    String cleaned = nullIndex != -1 ? rawName.substring(0, nullIndex) : rawName;

    // Remove any remaining control characters and non-printable characters
    cleaned = cleaned.replaceAll(RegExp(r'[^\x20-\x7E]'), '');

    // Trim whitespace
    cleaned = cleaned.trim();

    // Game Boy titles should be max 15 characters
    if (cleaned.length > 15) {
      cleaned = cleaned.substring(0, 15).trim();
    }

    // Remove any trailing non-alphanumeric characters (but keep spaces)
    while (cleaned.isNotEmpty &&
           !RegExp(r'[A-Za-z0-9\s]').hasMatch(cleaned[cleaned.length - 1])) {
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    // Final trim
    cleaned = cleaned.trim();

    // If empty after cleaning, return filename-based fallback
    if (cleaned.isEmpty) {
      return 'Unknown ROM';
    }

    return cleaned;
  }

  static String _fileNameFromPath(String path) {
    return path.split('/').last;
  }

  static bool _isTestRom(String path, String fileName) {
    final pathLower = path.toLowerCase();
    final fileLower = fileName.toLowerCase();

    return pathLower.contains('blargg') ||
           pathLower.contains('mooneye') ||
           pathLower.contains('development') ||
           pathLower.contains('test') ||
           fileLower.contains('test') ||
           fileLower.contains('acid') ||
           fileLower.contains('cpu_instrs') ||
           fileLower.contains('timing') ||
           fileLower.contains('interrupt') ||
           fileLower.contains('halt') ||
           fileLower.contains('opus') ||
           fileLower.contains('dmg-acid') ||
           fileLower.contains('cgb-acid') ||
           fileLower.contains('oam_bug') ||
           fileLower.contains('mem_timing') ||
           fileLower.contains('sound') ||
           fileLower.contains('example') ||
           fileLower.contains('paint') ||
           fileLower.contains('galaxy') ||
           fileLower.contains('crash') ||
           fileLower.contains('rand') ||
           fileLower.contains('comm') ||
           fileLower.contains('irq') ||
           fileLower.contains('hicolor') ||
           fileLower.contains('gbtype') ||
           fileLower.contains('colorbar') ||
           fileLower.contains('space') ||
           fileLower.contains('dscan') ||
           fileLower.contains('filltest') ||
           fileLower.contains('dtmf') ||
           fileLower.contains('pong') ||
           fileLower.contains('border') ||
           fileLower.contains('rpn') ||
           fileLower.contains('wobble');
  }

  static Future<List<RomInfo>> _scanForRomsFromManifest(Map<String, dynamic> manifest) async {
    final List<RomInfo> roms = [];
    final romPaths = List<String>.from(manifest['rom_files'] ?? []);

    print('Scanning ${romPaths.length} ROM files from manifest...');

    for (final romPath in romPaths) {
      try {
        // Load the ROM data using the emulator's cartridge system
        final ByteData romData = await rootBundle.load(romPath);
        final romBytes = romData.buffer.asUint8List();

        // Create a cartridge instance to read header data
        final cartridge = Cartridge();
        cartridge.load(romBytes);

        // Extract information from the cartridge
        final fileName = _fileNameFromPath(romPath);

        // Debug: Print raw cartridge name with byte codes
        print('Raw cartridge name for $fileName: "${cartridge.name}"');
        print('Raw bytes: ${cartridge.name.codeUnits}');

        String cartridgeName = _cleanCartridgeName(cartridge.name);
        print('Cleaned cartridge name: "$cartridgeName"');

        // If cartridge name is still empty/unknown, use filename as fallback
        if (cartridgeName == 'Unknown ROM' || cartridgeName.isEmpty) {
          cartridgeName = fileName.replaceAll(RegExp(r'\.(gb|gbc)$'), '');
          cartridgeName = cartridgeName.replaceAll('_', ' ');
          cartridgeName = cartridgeName.split(' ').map((word) =>
            word.isEmpty ? '' : word[0].toUpperCase() + word.substring(1)
          ).join(' ');
          print('Using filename-based name: "$cartridgeName"');
        }

        // Determine platform based on cartridge data
        String platform = 'Game Boy';
        if (fileName.endsWith('.gbc') || cartridge.gameboyType == GameboyType.color) {
          platform = 'Game Boy Color';
        }

        final isTestRom = _isTestRom(romPath, fileName);

        roms.add(RomInfo(
          name: cartridgeName,
          path: romPath,
          platform: platform,
          fileName: fileName,
          isTestRom: isTestRom,
        ));

        print('Loaded ROM: "$cartridgeName" (${cartridge.gameboyType.name}) - $fileName');
      } catch (e) {
        print('Error loading ROM $romPath: $e');
        continue;
      }
    }

    // Sort ROMs: games first, then test ROMs, alphabetically within each group
    roms.sort((a, b) {
      if (a.isTestRom != b.isTestRom) {
        return a.isTestRom ? 1 : -1; // Games first
      }
      return a.name.compareTo(b.name);
    });

    print('Successfully loaded ${roms.length} ROMs using emulator cartridge system');
    return roms;
  }

  static Future<void> _cacheRoms(List<RomInfo> roms, String manifestHash) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = json.encode(roms.map((rom) => rom.toJson()).toList());

      await prefs.setString(_cacheKey, jsonString);
      await prefs.setString(_versionKey, _currentVersion);
      await prefs.setString(_manifestKey, manifestHash);
      print('Cached ${roms.length} ROMs with manifest hash');
    } catch (e) {
      print('Failed to cache ROMs: $e');
    }
  }

  static Future<void> clearCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_cacheKey);
      await prefs.remove(_versionKey);
      await prefs.remove(_manifestKey);
      print('ROM cache cleared');
    } catch (e) {
      print('Failed to clear cache: $e');
    }
  }

  static Future<void> refreshRomList() async {
    await clearCache();
    await getAvailableRoms();
  }
}