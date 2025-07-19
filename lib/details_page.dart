// details_page.dart

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'dart:async';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'Services/config_loader.dart';

class DetailsPage extends StatefulWidget {
  const DetailsPage({super.key});

  @override
  State<DetailsPage> createState() => _DetailsPageState();
}

class _DetailsPageState extends State<DetailsPage> with WidgetsBindingObserver {
  // State variables for each ComboBox selection
  bool _showAdhocSection = false; // Label8, ComboBox6, Label9, ComboBox8
  final TextEditingController _crossingNumberController =
      TextEditingController(); // Edit1
  String _currentFileName = 'File Name:'; // Label7 text

  // Mock for LocationSensor (Delphi's LocationSensor1)
  String _latitude = 'N/A';
  String _longitude = 'N/A';

  late ConfigLoader _configLoader;
  late DropdownManager _dropdownManager;
  bool _isConfigLoaded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configLoader = ConfigLoader();
    _tryLoadConfig();

    _updateLocation();
  }

  @override // ADD THIS LINE
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_isConfigLoaded) {
      _tryLoadConfig();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _crossingNumberController.dispose();
    super.dispose();
  }

  void _tryLoadConfig() async {
    try {
      await _configLoader.loadConfig();
      setState(() {
        _dropdownManager = DropdownManager(_configLoader);
        _isConfigLoaded = true;
        _updateFileName();
      });
    } catch (e) {
      print('Error loading config: $e');
      if (e.toString().toLowerCase().contains('permission')) {
        final opened = await openAppSettings();
        if (opened) {
          await Future.delayed(const Duration(seconds: 2));
          _tryLoadConfig();
        }
      }
    }
  }

  Future<void> _updateLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _latitude = 'Location services disabled';
          _longitude = 'Location services disabled';
        });
        print('Location Error: Services are disabled on the device.');
        // Consider directing the user to enable services: await Geolocator.openLocationSettings();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        print(
          'Location Debug: Permission denied previously, requesting now...',
        );
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _latitude = 'Permission denied';
            _longitude = 'Permission denied';
          });
          print('Location Error: Permission was denied by the user.');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _latitude = 'Permission denied forever';
          _longitude = 'Permission denied forever';
        });
        print(
          'Location Error: Permission permanently denied. User needs to enable in settings.',
        );
        // This is where you might want to prompt the user to open app settings:
        // await Geolocator.openAppSettings();
        return;
      }

      print(
        'DEBUG: Permissions granted, attempting to get current position...',
      );

      // Set desired accuracy before the position request
      // --- CRUCIAL CHANGE: Add a timeout to getCurrentPosition ---
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low,
      ).timeout(const Duration(seconds: 30));

      setState(() {
        _latitude = position.latitude.toStringAsFixed(
          6,
        ); // Format for readability
        _longitude = position.longitude.toStringAsFixed(
          6,
        ); // Format for readability
      });
      print('Location Success: Lat: $_latitude, Lng: $_longitude');
    } on TimeoutException catch (e) {
      // This specifically catches the timeout error
      setState(() {
        _latitude = 'Timeout';
        _longitude = 'Timeout';
      });
      print(
        'Location Error (TimeoutException): The location request timed out. This often happens indoors or with poor GPS signal. Error: $e',
      );
    } on LocationServiceDisabledException catch (e) {
      // Catches if location services are disabled *during* the request
      setState(() {
        _latitude = 'Services disabled';
        _longitude = 'Services disabled';
      });
      print(
        'Location Error (LocationServiceDisabledException): Location services were disabled during the request. Error: $e',
      );
    } catch (e) {
      // General catch-all for any other unexpected errors
      setState(() {
        _latitude = 'Unknown Error';
        _longitude = 'Unknown Error';
      });
      print('Location Error (Unknown): An unexpected error occurred: $e');
    }
  }

  void _updateFileName() {
    // If we reach here, _dropdownManager is guaranteed to be non-null.
    // Use a local non-nullable variable for cleaner access.
    final dropdownManager = _dropdownManager;

    String s = '';
    try {
      final String? prefix = dropdownManager.selections['Prefix'];
      final String? crossingType = dropdownManager.selections['Crossing Type'];
      final String? crossingNumber =
          dropdownManager.selections['Crossing Number'];

      final String? crossingNumberSuffix =
          dropdownManager.selections['Crossing Number Suffix'];
      final String? crossingLocation =
          dropdownManager.selections['Crossing Location'];
      final String? photoCode = dropdownManager.selections['Photo Code'];
      final String? adhocCode = dropdownManager.selections['Adhoc Code'];
      final String? imageSeq = dropdownManager.selections['Image Seq'];

      s += prefix ?? '';
      s += crossingNumber?.trim() ?? ''; // Trim text field value

      if (crossingType == '_PD') {
        // If ped crossing
        if (crossingNumberSuffix != null && crossingNumberSuffix.isNotEmpty) {
          s += '-${crossingNumberSuffix}'; // ped suffix
        }
        s += crossingType ?? ''; // crossing type
        s += crossingLocation ?? ''; // ped location
      } else {
        // Road crossing
        s += crossingType ?? '';
      }

      s += photoCode ?? '';
      if (dropdownManager.selections['Approach'] == 'Adhoc') {
        // _showAdhocSection's logic is assumed to be handled elsewhere
        s += adhocCode ?? '';
      }

      if (_showAdhocSection && imageSeq != null && imageSeq.isNotEmpty) {
        s += '_${imageSeq}';
      }
      _currentFileName = 'File Name: $s.jpg';
    } catch (e) {
      _currentFileName = 'File Name: Error building filename';
      print('Error building filename: $e'); // For debugging
    }

    // Update the UI to reflect the calculated filename
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  // --- Helper Widget to build a labeled dropdown button ---

  @override
  Widget build(BuildContext context) {
    if (!_isConfigLoaded) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      backgroundColor: Colors.white, // claWheat equivalent
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row for XingPics version and Latitude/Longitude
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'XingPics - v19',
                  style: TextStyle(
                    fontSize: 14.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[800],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Latitude: $_latitude',
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      'Longitude: $_longitude',
                      style: TextStyle(
                        fontSize: 14.0,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Prefix (ComboBox1, Label2) - Y=63
            buildDropdown(
              label: 'Prefix',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection('Prefix', val, () {
                    // optionally reset dependent fields
                  });
                });
              },
            ),
            buildDropdown(
              label: 'Crossing Type',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection('Crossing Type', val, () {
                    // optionally reset dependent fields
                  });
                  _resetLaterFormFields(2);
                });
              },
            ),

            // The new Crossing Number Text Field
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              child: TextFormField(
                controller: _crossingNumberController,
                decoration: const InputDecoration(
                  labelText: 'Crossing Number',
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.text, // Suggests numeric input
                // onChanged is automatically handled by the controller's listener
                // If you need immediate reaction in other widgets, use onChanged to call setState
                onChanged: (value) {
                  setState(() {
                    _dropdownManager.updateSelection(
                      'Crossing Number',
                      value,
                      () {},
                    );
                  });
                },
              ),
            ),

            // Show Crossing Number Suffix only if Crossing Type is'_PD'
            buildDropdown(
              label: 'Crossing Number Suffix',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection(
                    'Crossing Number Suffix',
                    val,
                    () {},
                  );
                });
                _updateFileName();
              },
            ),
            // Show Crossing Number Suffix only if Crossing Type is'_PD'
            buildDropdown(
              label: 'Crossing Location',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection(
                    'Crossing Location',
                    val,
                    () {
                      // optionally reset dependent fields
                    },
                  );
                });
                _updateFileName();
              },
            ),

            buildDropdown(
              label: 'Approach',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection('Approach', val, () {
                    // optionally reset dependent fields
                  });
                });
                _updateFileName();
              },
            ),

            buildDropdown(
              label: 'Photo Code',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection('Photo Code', val, () {
                    // optionally reset dependent fields
                  });
                });
                _updateFileName();
                _resetLaterFormFields(3);
              },
            ),

            buildDropdown(
              label: 'Adhoc Code',
              manager: _dropdownManager,
              onChanged: (val) {
                setState(() {
                  _dropdownManager.updateSelection('Adhoc Code', val, () {});
                });
                _updateFileName();
              },
            ),

            const SizedBox(height: 30),

            // Buttons (Button4, Button1) - Y=510
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await _updateLocation();
                      await _takeAndSavePhoto();
                      _showSnackBar(
                        context,
                        'Take Photo clicked! Filename: $_currentFileName\nLat: $_latitude, Long: $_longitude',
                      );
                      // In a real app, integrate with camera plugin
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text(
                      'Take Photo',
                      style: TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _showSnackBar(context, 'Exiting the app ...');
                      // In a real app, you might navigate back or close the app
                      exit(0);
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text('Exit', style: TextStyle(fontSize: 16)),
                  ),
                ),
                /*Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      _resetAllFormFields();
                      _showSnackBar(context, 'Form reset!');
                      // In a real app, you might navigate back or close the app
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8.0),
                      ),
                    ),
                    child: const Text('Reset', style: TextStyle(fontSize: 16)),
                  ),
                ),*/
              ],
            ),
            const SizedBox(height: 30),

            // File Name Label (Label7) - Y=570
            Align(
              alignment: Alignment.center,
              child: Text(
                _currentFileName,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue[900], // Darkblue color
                ),
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  void _resetLaterFormFields(int seam) {
    // Clear all selections in the DropdownManager
    if (!_isConfigLoaded) {
      return; // Exit the method early
    }

    if (seam == 3) {
      // Reset specific fields for seam 3
    }
    if (seam == 2) {
      _dropdownManager.updateSelection('Crossing Number Suffix', null, () {});
      _dropdownManager.updateSelection('Crossing Location', null, () {});
      _dropdownManager.updateSelection('Photo Code', null, () {});
      _dropdownManager.updateSelection('Adhoc Code', null, () {});
      _dropdownManager.updateSelection('Image Seq', null, () {});
    }
    if (seam == 1) {
      _dropdownManager.updateSelection('Crossing Number Suffix', null, () {});
      _dropdownManager.updateSelection('Crossing Location', null, () {});
      _dropdownManager.updateSelection('Photo Code', null, () {});
      _dropdownManager.updateSelection('Adhoc Code', null, () {});
      _dropdownManager.updateSelection('Image Seq', null, () {});

      _dropdownManager.updateSelection('Crossing Number', null, () {});
      _dropdownManager.updateSelection('Crossing Type', null, () {});
    }

    // Recalculate the filename as all fields are reset
    _updateFileName();
    return;
  }

  void _resetAllFormFields() {
    // Clear all selections in the DropdownManager
    if (!_isConfigLoaded) {
      return; // Exit the method early
    }

    _dropdownManager.selections.keys.forEach((key) {
      _dropdownManager.updateSelection(key, null, () {});
    });

    // Recalculate the filename as all fields are reset
    _updateFileName();

    // Trigger a UI rebuild if not already handled by notifyListeners()
  }

  // Helper function to show a SnackBar message
  void _showSnackBar(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _takeAndSavePhoto() async {
    try {
      // STEP 1: Request permissions
      if (Platform.isAndroid) {
        final deviceInfo = DeviceInfoPlugin();
        final androidInfo = await deviceInfo.androidInfo;
        final int androidVersion = androidInfo.version.sdkInt ?? 30;

        if (androidVersion >= 33) {
          // Android 13+ granular permissions
          final photos = await Permission.photos.request();
          final camera = await Permission.camera.request();
          if (!photos.isGranted || !camera.isGranted) {
            _showSnackBar(context, 'Permissions not granted');
            return;
          }
        } else {
          // Android < 13
          final storage = await Permission.storage.request();
          final camera = await Permission.camera.request();
          if (!storage.isGranted || !camera.isGranted) {
            _showSnackBar(context, 'Permissions not granted');
            return;
          }
        }
      }

      // STEP 2: Take the photo
      final picker = ImagePicker();
      final XFile? photo = await picker.pickImage(source: ImageSource.camera);

      if (photo == null) {
        _showSnackBar(context, 'Photo capture cancelled.');
        return;
      }

      // STEP 3: Build date-based folder path
      final String today = DateTime.now()
          .toIso8601String()
          .substring(0, 10)
          .replaceAll('-', '');
      final String fileName = _currentFileName.replaceFirst('File Name: ', '');
      late final Directory saveDir;

      if (Platform.isAndroid) {
        saveDir = Directory('/storage/emulated/0/Pictures/XingPics/$today');
      } else if (Platform.isIOS) {
        final dir = await getApplicationDocumentsDirectory();
        saveDir = Directory(path.join(dir.path, 'XingPics', today));
      } else {
        _showSnackBar(context, 'Unsupported platform');
        return;
      }

      // STEP 4: Create folder and save image
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      //appending incrementer to file name if it already exists

      String baseName = path.basenameWithoutExtension(fileName);
      String extension = path.extension(fileName);
      String finalFileName = fileName;

      // Check if the initial file name exists
      String initialSavePath = path.join(saveDir.path, fileName);
      if (await File(initialSavePath).exists()) {
        int counter = 1; // Start counter at 1 for the first duplicate
        // Keep incrementing until a unique file name is found
        while (await File(
          path.join(saveDir.path, '$baseName-$counter$extension'),
        ).exists()) {
          counter++;
        }
        finalFileName = '$baseName-$counter$extension';
      }

      final String savePath = path.join(saveDir.path, finalFileName);
      final File savedImage = await File(photo.path).copy(savePath);

      _showSnackBar(context, '✅ Saved to:\n${savedImage.path}');
      print('✅ Photo saved at: $savePath');
    } catch (e) {
      print('❌ Error taking/saving photo: $e');
      _showSnackBar(context, 'Error: $e');
    }
  }
}
