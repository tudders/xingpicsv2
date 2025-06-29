// Fixed version with corrected rule parsing and application logic
// Dependencies: csv, path_provider, permission_handler

import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class ConfigLoader {
  late Map<String, List<String>> dropdownOptions;
  late List<Rule> rules;

  Future<void> requestStoragePermission() async {
    final status = await Permission.manageExternalStorage.request();
    print('Permission status: $status');
    if (!status.isGranted) {
      throw Exception('Storage permission not granted');
    }
  }

  Future<void> loadConfig() async {
    await requestStoragePermission();
    final dir = Directory('/storage/emulated/0/XingPics');

    if (!await dir.exists()) {
      throw Exception('XingPics folder not found at: ${dir.path}');
    }

    final optionsFile = File('${dir.path}/values.csv');
    final rulesFile = File('${dir.path}/rules.csv');

    dropdownOptions = {};
    rules = [];

    // Load dropdown options from values.csv
    if (await optionsFile.exists()) {
      final optionsCsv = await optionsFile.readAsString();
      final optionsRows = const CsvToListConverter().convert(
        optionsCsv,
        eol: '\n',
      );

      for (var row in optionsRows.skip(1)) {
        if (row.length >= 2) {
          final label = row[0].toString().trim();
          final value = row[1].toString().trim();
          if (label.isNotEmpty && value.isNotEmpty) {
            dropdownOptions.putIfAbsent(label, () => []).add(value);
          }
        }
      }
    } else {
      print('Options CSV not found at ${optionsFile.path}');
    }

    // Load rules from rules.csv
    if (await rulesFile.exists()) {
      final rulesCsv = await rulesFile.readAsString();
      final rulesRows = const CsvToListConverter().convert(rulesCsv, eol: '\n');

      for (var row in rulesRows.skip(1)) {
        if (row.length >= 8) {
          try {
            final rule = Rule.fromRow(row);
            rules.add(rule);
            print('Loaded rule: $rule'); // Debug output
          } catch (e) {
            print('Error parsing rule from row $row: $e');
          }
        }
      }
    } else {
      print('Rules CSV not found at ${rulesFile.path}');
    }

    print('Loaded dropdown options: ${dropdownOptions.keys}');
    print('Loaded ${rules.length} rules');

    // Debug: Print first few rules
    for (int i = 0; i < rules.length && i < 10; i++) {
      print('Rule $i: ${rules[i]}');
    }
  }

  List<String> getValidOptions(
    String targetDropdown,
    Map<String, String?> currentSelections,
  ) {
    print(
      'Getting valid options for $targetDropdown with selections: $currentSelections',
    );

    // Get base options from values.csv
    final baseOptions = dropdownOptions[targetDropdown] ?? [];
    print('Base options for $targetDropdown: $baseOptions');

    // Check if any rules apply to this dropdown
    final applicableRules = rules
        .where((rule) => rule.targetDropdown == targetDropdown)
        .toList();
    print(
      'Found ${applicableRules.length} applicable rules for $targetDropdown',
    );

    // If no rules exist for this dropdown, return all base options
    if (applicableRules.isEmpty) {
      print('No rules found, returning all base options');
      return baseOptions;
    }

    // Filter selections to only include non-null values
    final filteredSelections = Map<String, String>.fromEntries(
      currentSelections.entries
          .where((e) => e.value != null && e.value!.isNotEmpty)
          .map((e) => MapEntry(e.key, e.value!)),
    );
    print('Filtered selections: $filteredSelections');

    // Find matching rules
    final matchingRules = applicableRules.where((rule) {
      final matches = rule.matches(filteredSelections);
      print('Rule ${rule.toString()} matches: $matches');
      return matches;
    }).toList();

    print('Found ${matchingRules.length} matching rules');

    // If no rules match, return empty list (no valid options)
    if (matchingRules.isEmpty) {
      print('No matching rules, returning empty list');
      return [];
    }

    // Get allowed values from matching rules
    final allowedValues = matchingRules.map((r) => r.allowedValue).toSet();
    print('Allowed values: $allowedValues');

    // Return the allowed values directly (they don't need to be in base options)
    return allowedValues.toList();
  }

  Map<String, List<String>> buildDependencyMapFromRules(List<Rule> rules) {
    final Map<String, Set<String>> tempMap = {};

    for (final rule in rules) {
      for (final parent in rule.conditions.keys) {
        tempMap.putIfAbsent(parent, () => {}).add(rule.targetDropdown);
      }
    }

    final depMap = tempMap.map((key, value) => MapEntry(key, value.toList()));
    print('Built dependency map: $depMap');
    return depMap;
  }
}

class Rule {
  final Map<String, String> conditions;
  final String targetDropdown;
  final String allowedValue;

  Rule({
    required this.conditions,
    required this.targetDropdown,
    required this.allowedValue,
  });

  bool matches(Map<String, String> selections) {
    // If rule has no conditions, it always matches (unconditional rule)
    if (conditions.isEmpty) {
      return true;
    }

    // Check if this rule can be satisfied by current selections
    // A rule matches if ALL its conditions are satisfied by selections
    // BUT we also need to handle partial matches where not all required dropdowns are selected yet

    bool hasRelevantSelections = false;

    for (final entry in conditions.entries) {
      final conditionDropdown = entry.key;
      final conditionValue = entry.value;

      if (selections.containsKey(conditionDropdown)) {
        hasRelevantSelections = true;
        // If we have a selection for this condition dropdown, it must match
        if (selections[conditionDropdown] != conditionValue) {
          return false; // This condition is not satisfied
        }
      }
    }

    // If we have relevant selections and haven't returned false yet,
    // it means all checked conditions are satisfied
    // If we have no relevant selections at all, this rule doesn't apply yet
    return hasRelevantSelections;
  }

  factory Rule.fromRow(List<dynamic> row) {
    // Expected CSV format:
    // IfDropdown1,IfValue1,IfDropdown2,IfValue2,IfDropdown3,IfValue3,TargetDropdown,AllowedValue

    if (row.length < 8) {
      throw ArgumentError('Row must have at least 8 columns');
    }

    final conditions = <String, String>{};

    // Parse condition pairs from first 6 columns
    for (int i = 0; i < 6; i += 2) {
      final dropdown = row[i].toString().trim();
      final value = row[i + 1].toString().trim();

      if (dropdown.isNotEmpty && value.isNotEmpty) {
        conditions[dropdown] = value;
      }
    }

    // Target dropdown is column 6 (index 6)
    final targetDropdown = row[6].toString().trim();
    // Allowed value is column 7 (index 7)
    final allowedValue = row[7].toString().trim();

    if (targetDropdown.isEmpty || allowedValue.isEmpty) {
      throw ArgumentError('Target dropdown and allowed value cannot be empty');
    }

    return Rule(
      conditions: conditions,
      targetDropdown: targetDropdown,
      allowedValue: allowedValue,
    );
  }

  @override
  String toString() {
    return 'Rule(conditions: $conditions, target: $targetDropdown, allowed: $allowedValue)';
  }
}

class DropdownManager {
  final ConfigLoader loader;
  late final Map<String, String?> selections;
  late final Map<String, List<String>> dependencyMap;
  late final Set<String> dropdownsInRules;

  DropdownManager(this.loader) {
    // Initialize selections with all possible dropdowns from loader.dropdownOptions
    selections = {for (var key in loader.dropdownOptions.keys) key: null};
    dependencyMap = loader.buildDependencyMapFromRules(loader.rules);

    // Populate the set of dropdowns that are targetDropdowns in any rule.
    dropdownsInRules = loader.rules.map((rule) => rule.targetDropdown).toSet();
    print('Dropdowns present in rules as targets: $dropdownsInRules');
  }

  void updateSelection(String key, String? value, void Function() callback) {
    print('Updating selection: $key = $value');
    selections[key] = value;
    resetDependents(key);
    callback();
  }

  void resetDependents(String key) {
    if (!dependencyMap.containsKey(key)) return;

    print('Resetting dependents of $key: ${dependencyMap[key]}');
    for (final dep in dependencyMap[key]!) {
      selections[dep] = null;
      resetDependents(dep); // recursive reset
    }
  }

  List<String> getOptions(String dropdownLabel) {
    final options = loader.getValidOptions(dropdownLabel, selections);
    print('Options for $dropdownLabel: $options');
    return options;
  }

  bool isVisible(String dropdownLabel) {
    // If a dropdown is NOT a target in any rule, it should always be visible
    // as long as it has options defined in values.csv.
    if (!dropdownsInRules.contains(dropdownLabel)) {
      final visible =
          (loader.dropdownOptions[dropdownLabel]?.isNotEmpty ?? false);
      print('Dropdown $dropdownLabel visible (not in rules): $visible');
      return visible;
    }

    // For dropdowns that are targets in conditional rules,
    // check if there are any valid options based on current selections
    final options = getOptions(dropdownLabel);
    final visible = options.isNotEmpty;
    print('Dropdown $dropdownLabel visible (conditional rules): $visible');
    return visible;
  }
}

Widget buildDropdown({
  required String label,
  required DropdownManager manager,
  required void Function(String? value) onChanged,
}) {
  if (!manager.isVisible(label)) {
    return const SizedBox.shrink(); // Hide dropdown if not visible
  }

  final options = manager.getOptions(label);
  final currentValue = manager.selections[label];

  // Reset selection if current value is not in valid options
  if (currentValue != null && !options.contains(currentValue)) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      onChanged(null);
    });
  }

  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 8.0),
    child: DropdownButtonFormField<String>(
      value: options.contains(currentValue) ? currentValue : null,
      items: options
          .map((val) => DropdownMenuItem(value: val, child: Text(val)))
          .toList(),
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      isExpanded: true,
    ),
  );
}
