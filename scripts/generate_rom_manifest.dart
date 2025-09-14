#!/usr/bin/env dart

import 'dart:io';
import 'dart:convert';

void main() {
  // Get the project root directory
  final projectRoot = Directory.current.path;
  final romsDir = Directory('$projectRoot/assets/roms');

  if (!romsDir.existsSync()) {
    print('ROM directory not found: ${romsDir.path}');
    exit(1);
  }

  final romFiles = <String>[];

  // Recursively scan for ROM files
  _scanDirectory(romsDir, '', romFiles);

  // Generate the manifest
  final manifest = {
    'generated_at': DateTime.now().toIso8601String(),
    'rom_files': romFiles,
  };

  // Write the manifest to assets
  final manifestFile = File('$projectRoot/assets/rom_manifest.json');
  manifestFile
      .writeAsStringSync(const JsonEncoder.withIndent('  ').convert(manifest));

  print('Generated ROM manifest with ${romFiles.length} ROM files');
  print('Manifest saved to: ${manifestFile.path}');

  // Print found ROMs for debugging
  for (final rom in romFiles) {
    print('  - $rom');
  }
}

void _scanDirectory(Directory dir, String relativePath, List<String> romFiles) {
  try {
    final entities = dir.listSync();

    for (final entity in entities) {
      if (entity is File) {
        final fileName = entity.uri.pathSegments.last;
        if (fileName.endsWith('.gb') || fileName.endsWith('.gbc')) {
          final assetPath = relativePath.isEmpty
              ? 'assets/roms/$fileName'
              : 'assets/roms/$relativePath/$fileName';
          romFiles.add(assetPath);
        }
      } else if (entity is Directory) {
        final dirName =
            entity.uri.pathSegments[entity.uri.pathSegments.length - 2];
        final newRelativePath =
            relativePath.isEmpty ? dirName : '$relativePath/$dirName';
        _scanDirectory(entity, newRelativePath, romFiles);
      }
    }
  } catch (e) {
    print('Error scanning directory ${dir.path}: $e');
  }
}
