import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

const String mapApiUrl = 'https://mp-cjn5.onrender.com';
const Color emerald = Color(0xFF00805F);
const Color navy = Color(0xFF101B2D);

// -----------------------------------------------------------------------------
// DATA MODELS
// -----------------------------------------------------------------------------

class ClimateLocation {
  final String name;
  final double latitude;
  final double longitude;

  const ClimateLocation({
    required this.name,
    required this.latitude,
    required this.longitude,
  });
}

class ForecastGridPoint {
  final double latitude;
  final double longitude;
  final double value;

  const ForecastGridPoint({
    required this.latitude,
    required this.longitude,
    required this.value,
  });

  factory ForecastGridPoint.fromJson(Map<String, dynamic> json) {
    final lat = json['latitude'];
    final lon = json['longitude'];
    final rawValue = json['value'];

    return ForecastGridPoint(
      latitude: lat is num ? lat.toDouble() : 0,
      longitude: lon is num ? lon.toDouble() : 0,
      value: rawValue is num ? rawValue.toDouble() : double.nan,
    );
  }
}

class WindGridPoint {
  final double latitude;
  final double longitude;
  final double uKmh;
  final double vKmh;
  final double speedKmh;

  const WindGridPoint({
    required this.latitude,
    required this.longitude,
    required this.uKmh,
    required this.vKmh,
    required this.speedKmh,
  });

  factory WindGridPoint.fromJson(Map<String, dynamic> json) {
    double number(String key) {
      final value = json[key];
      return value is num ? value.toDouble() : 0.0;
    }

    return WindGridPoint(
      latitude: number('latitude'),
      longitude: number('longitude'),
      uKmh: number('u_kmh'),
      vKmh: number('v_kmh'),
      speedKmh: number('wind_speed_kmh'),
    );
  }
}

const List<ClimateLocation> climateLocations = [
  ClimateLocation(
    name: 'Thiruvananthapuram',
    latitude: 8.5241,
    longitude: 76.9366,
  ),
  ClimateLocation(name: 'Kollam', latitude: 8.8932, longitude: 76.6141),
  ClimateLocation(name: 'Pathanamthitta', latitude: 9.2648, longitude: 76.7870),
  ClimateLocation(name: 'Alappuzha', latitude: 9.4981, longitude: 76.3388),
  ClimateLocation(name: 'Kottayam', latitude: 9.5916, longitude: 76.5222),
  ClimateLocation(name: 'Idukki', latitude: 9.8494, longitude: 76.9720),
  ClimateLocation(name: 'Kochi', latitude: 9.9312, longitude: 76.2673),
  ClimateLocation(name: 'Thrissur', latitude: 10.5276, longitude: 76.2144),
  ClimateLocation(name: 'Palakkad', latitude: 10.7867, longitude: 76.6548),
  ClimateLocation(name: 'Malappuram', latitude: 11.0510, longitude: 76.0711),
  ClimateLocation(name: 'Kozhikode', latitude: 11.2588, longitude: 75.7804),
  ClimateLocation(name: 'Wayanad', latitude: 11.6854, longitude: 76.1320),
  ClimateLocation(name: 'Kannur', latitude: 11.8745, longitude: 75.3704),
  ClimateLocation(name: 'Kasaragod', latitude: 12.4996, longitude: 74.9869),
];

// -----------------------------------------------------------------------------
// MAP SCREEN
// -----------------------------------------------------------------------------

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();

  late final AnimationController _windAnimation;

  Map<String, Map<String, dynamic>> weatherData = {};
  List<WindGridPoint> windGrid = [];
  List<ForecastGridPoint> forecastGrid = [];
  Timer? _forecastGridDebounce;
  bool isForecastGridLoading = false;
  String? forecastGridError;
  String? _lastForecastGridRequest;

  String selectedDistrict = 'Kochi';
  String displayMode = 'Wind';
  int selectedForecastIndex = 0;

  bool isLoading = true;
  bool showLegend = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    _windAnimation = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();

    fetchAllWeather();
    fetchWindGrid();
  }

  @override
  void dispose() {
    _forecastGridDebounce?.cancel();
    _windAnimation.dispose();
    _mapController.dispose();
    super.dispose();
  }

  // Load weather for all district locations.
  Future<void> fetchAllWeather() async {
    if (!mounted) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    final results = <String, Map<String, dynamic>>{};
    final errors = <String>[];

    await Future.wait(
      climateLocations.map((location) async {
        try {
          final response = await http
              .get(
                Uri.parse(
                  '$mapApiUrl/api/weather/'
                  '${Uri.encodeComponent(location.name)}',
                ),
              )
              .timeout(const Duration(seconds: 25));

          if (response.statusCode == 200) {
            final decoded = jsonDecode(response.body);

            if (decoded is Map<String, dynamic>) {
              results[location.name] = decoded;
            } else {
              errors.add(location.name);
            }
          } else {
            errors.add(location.name);
          }
        } catch (_) {
          errors.add(location.name);
        }
      }),
    );

    if (!mounted) return;

    setState(() {
      weatherData = results;
      isLoading = false;

      if (results.isEmpty) {
        errorMessage = 'Could not load weather. Check the backend connection.';
      } else if (errors.isNotEmpty) {
        errorMessage =
            '${results.length} of ${climateLocations.length} locations loaded';
      }
    });
  }

  // Load the gridded wind vectors from FastAPI.
  Future<void> fetchWindGrid() async {
    try {
      final response = await http
          .get(Uri.parse('$mapApiUrl/api/climate/wind-grid'))
          .timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) return;

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) return;

      final rawPoints = decoded['points'];

      if (rawPoints is! List) return;

      final parsed = rawPoints
          .whereType<Map<String, dynamic>>()
          .map(WindGridPoint.fromJson)
          .toList();

      if (!mounted || parsed.isEmpty) return;

      setState(() {
        windGrid = parsed;
      });
    } catch (_) {
      // District weather and fallback wind animation can still work.
    }
  }

  // Fetch a gridded forecast for the currently selected variable and hour.
  // Slider changes are debounced so dragging does not flood the backend with requests.
  void scheduleForecastGridFetch({bool immediate = false}) {
    if (displayMode == 'Wind') return;

    _forecastGridDebounce?.cancel();

    if (immediate) {
      fetchForecastGrid();
    } else {
      _forecastGridDebounce = Timer(
        const Duration(milliseconds: 350),
        fetchForecastGrid,
      );
    }
  }

  Future<void> fetchForecastGrid() async {
    if (!mounted || displayMode == 'Wind') return;

    final variable = displayMode == 'Temperature' ? 'temperature' : 'rainfall';
    final hour = selectedForecastIndex.clamp(0, 71);
    final requestKey = '$variable:$hour';

    if (_lastForecastGridRequest == requestKey && forecastGrid.isNotEmpty) {
      return;
    }

    if (mounted) {
      setState(() {
        isForecastGridLoading = true;
        forecastGridError = null;
      });
    }

    try {
      final uri = Uri.parse(
        '$mapApiUrl/api/climate/forecast-grid'
        '?hour=$hour&variable=$variable',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('Forecast grid returned HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['points'] is! List) {
        throw const FormatException('Invalid forecast-grid response');
      }

      final points = (decoded['points'] as List)
          .whereType<Map<String, dynamic>>()
          .map(ForecastGridPoint.fromJson)
          .where((point) => point.value.isFinite)
          .toList();

      if (!mounted) return;

      // Ignore a response if the user changed the mode/hour while it loaded.
      final currentVariable = displayMode == 'Temperature'
          ? 'temperature'
          : 'rainfall';
      if (displayMode == 'Wind' ||
          currentVariable != variable ||
          selectedForecastIndex.clamp(0, 71) != hour) {
        return;
      }

      setState(() {
        forecastGrid = points;
        _lastForecastGridRequest = requestKey;
        isForecastGridLoading = false;
        forecastGridError = points.isEmpty
            ? 'No forecast grid data returned.'
            : null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        isForecastGridLoading = false;
        forecastGridError = 'Forecast overlay unavailable';
      });
    }
  }

  void refreshData() {
    fetchAllWeather();
    fetchWindGrid();
    _lastForecastGridRequest = null;
    if (displayMode != 'Wind') {
      scheduleForecastGridFetch(immediate: true);
    }
  }

  double? numericValue(Map<String, dynamic>? data, String key) {
    final value = data?[key];
    return value is num ? value.toDouble() : null;
  }

  List<dynamic> _hourlyValues(Map<String, dynamic>? data, String key) {
    final hourly = data?['hourly'];
    if (hourly is! Map<String, dynamic>) return const [];
    final values = hourly[key];
    return values is List ? values : const [];
  }

  // Read the value for the hour currently selected by the forecast slider.
  double? _forecastValue(Map<String, dynamic>? data, String key) {
    final values = _hourlyValues(data, key);
    if (values.isEmpty) return null;

    final index = selectedForecastIndex.clamp(0, values.length - 1);
    final value = values[index];
    return value is num ? value.toDouble() : null;
  }

  int get _forecastLength {
    final times = _hourlyValues(weatherData[selectedDistrict], 'time');
    return times.length;
  }

  String get _selectedForecastTime {
    final times = _hourlyValues(weatherData[selectedDistrict], 'time');
    if (times.isEmpty) return 'Forecast time unavailable';
    final index = selectedForecastIndex.clamp(0, times.length - 1);
    final raw = times[index];
    if (raw is! String) return 'Forecast time unavailable';
    try {
      final parsed = DateTime.parse(raw);
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      final hour = parsed.hour == 0
          ? 12
          : parsed.hour > 12
          ? parsed.hour - 12
          : parsed.hour;
      final period = parsed.hour >= 12 ? 'PM' : 'AM';
      return '${months[parsed.month - 1]} ${parsed.day} · $hour:00 $period';
    } catch (_) {
      return raw;
    }
  }

  String formatValue(Map<String, dynamic>? data, String key, String unit) {
    final value = numericValue(data, key);
    return value == null ? '--' : '${value.toStringAsFixed(1)}$unit';
  }

  String _conditionLabel(Map<String, dynamic>? data) {
    final code = numericValue(data, 'weather_code');
    final wind = numericValue(data, 'wind_speed_kmh');
    final rain = numericValue(data, 'precipitation_mm');

    if (code != null && code >= 95) return 'Storm';
    if (rain != null && rain >= 2) return 'Rainy';
    if (wind != null && wind >= 25) return 'Windy';
    if (code != null && code >= 1 && code <= 3) return 'Cloudy';
    return 'Clear';
  }

  Color markerColor(double value) {
    if (displayMode == 'Rainfall') {
      if (value < 0.5) return const Color(0xFF4CAF50);
      if (value < 2) return const Color(0xFFFFC107);
      if (value < 5) return const Color(0xFFFF7043);
      return const Color(0xFF42A5F5);
    }

    if (value < 20) return const Color(0xFF42A5F5);
    if (value < 25) return const Color(0xFF26A69A);
    if (value < 30) return const Color(0xFFFFB300);

    return const Color(0xFFEF5350);
  }

  double get averageWindSpeed {
    final values = weatherData.values
        .map((data) => numericValue(data, 'wind_speed_kmh'))
        .whereType<double>()
        .toList();

    if (values.isEmpty) return 0.0;

    return values.reduce((a, b) => a + b) / values.length;
  }

  // Calculate average direction using circular averaging.
  double get averageWindDirection {
    final values = weatherData.values
        .map((data) => numericValue(data, 'wind_direction_degrees'))
        .whereType<double>()
        .toList();

    if (values.isEmpty) return 0.0;

    final sinSum = values
        .map((v) => math.sin(v * math.pi / 180))
        .fold<double>(0.0, (a, b) => a + b);

    final cosSum = values
        .map((v) => math.cos(v * math.pi / 180))
        .fold<double>(0.0, (a, b) => a + b);

    return (math.atan2(sinSum, cosSum) * 180 / math.pi + 360) % 360;
  }

  void selectLocation(ClimateLocation location) {
    setState(() {
      selectedDistrict = location.name;
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _districtSheet(location.name),
    );
  }

  void _showPointDetails(LatLng point) {
    // The forecast grid is sampled spatially; if it is not loaded, fall back
    // to the nearest district's current weather for a useful first response.
    final nearest = climateLocations.reduce((a, b) {
      final da =
          math.pow(a.latitude - point.latitude, 2) +
          math.pow(a.longitude - point.longitude, 2);
      final db =
          math.pow(b.latitude - point.latitude, 2) +
          math.pow(b.longitude - point.longitude, 2);
      return da <= db ? a : b;
    });

    final nearestData = weatherData[nearest.name];
    final gridValue = _interpolateForecastValue(point);

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final valueLabel = displayMode == 'Temperature'
            ? 'Temperature'
            : displayMode == 'Rainfall'
            ? 'Precipitation'
            : 'Wind speed';

        final valueText = displayMode == 'Wind'
            ? formatValue(nearestData, 'wind_speed_kmh', ' km/h')
            : gridValue == null
            ? 'Unavailable'
            : displayMode == 'Temperature'
            ? '${gridValue.toStringAsFixed(1)} °C'
            : '${gridValue.toStringAsFixed(1)} mm';

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
              color: Color(0xFFF8FBFA),
              borderRadius: BorderRadius.all(Radius.circular(26)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: emerald),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Selected map point',
                        style: const TextStyle(
                          color: navy,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(sheetContext),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                Text(
                  '${point.latitude.toStringAsFixed(4)}, '
                  '${point.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: navy,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        displayMode == 'Wind'
                            ? Icons.air_rounded
                            : displayMode == 'Temperature'
                            ? Icons.thermostat_rounded
                            : Icons.water_drop_rounded,
                        color: const Color(0xFF8EF0C5),
                        size: 30,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              valueLabel,
                              style: const TextStyle(
                                color: Color(0xFFB8C8D8),
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              valueText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 25,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        Icons.location_city_rounded,
                        'Nearest district',
                        nearest.name,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 18,
                  runSpacing: 12,
                  children: [
                    _metric(
                      Icons.opacity_rounded,
                      'Humidity',
                      formatValue(nearestData, 'humidity_percent', '%'),
                    ),
                    _metric(
                      Icons.air_rounded,
                      'Wind',
                      formatValue(nearestData, 'wind_speed_kmh', ' km/h'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Forecast: $_selectedForecastTime',
                  style: const TextStyle(color: Colors.black54, fontSize: 11),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Grid values are interpolated from the forecast samples. '
                  'Other metrics shown are from the nearest district.',
                  style: TextStyle(color: Colors.black45, fontSize: 10),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double? _interpolateForecastValue(LatLng point) {
    if (forecastGrid.isEmpty) return null;

    final nearby = forecastGrid.map((sample) {
      final dx =
          (sample.longitude - point.longitude) *
          math.cos(point.latitude * math.pi / 180);
      final dy = sample.latitude - point.latitude;
      final distanceSquared = dx * dx + dy * dy;
      return (sample: sample, distanceSquared: distanceSquared);
    }).toList()..sort((a, b) => a.distanceSquared.compareTo(b.distanceSquared));

    double weighted = 0;
    double totalWeight = 0;

    for (final item in nearby.take(4)) {
      if (item.distanceSquared < 0.000001) {
        return item.sample.value;
      }

      final weight = 1 / item.distanceSquared;
      weighted += item.sample.value * weight;
      totalWeight += weight;
    }

    return totalWeight == 0 ? null : weighted / totalWeight;
  }

  // ---------------------------------------------------------------------------
  // DISTRICT WEATHER DETAILS
  // ---------------------------------------------------------------------------

  Widget _metric(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 19, color: emerald),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                  color: navy,
                ),
              ),
              Text(
                label,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _districtSheet(String district) {
    final data = weatherData[district];

    return SafeArea(
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 18),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(24),
            bottom: Radius.circular(24),
          ),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  const Icon(
                    Icons.location_on_rounded,
                    color: emerald,
                    size: 25,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      district,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: navy,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              if (data == null)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Text(
                    'Weather data is not available for this location.',
                  ),
                )
              else ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 20,
                  runSpacing: 18,
                  children: [
                    SizedBox(
                      width: 145,
                      child: _metric(
                        Icons.thermostat_rounded,
                        'Temperature',
                        formatValue(data, 'temperature_c', ' °C'),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: _metric(
                        Icons.water_drop_rounded,
                        'Current precipitation',
                        formatValue(data, 'precipitation_mm', ' mm'),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: _metric(
                        Icons.opacity_rounded,
                        'Humidity',
                        formatValue(data, 'humidity_percent', '%'),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: _metric(
                        Icons.air_rounded,
                        'Wind speed',
                        formatValue(data, 'wind_speed_kmh', ' km/h'),
                      ),
                    ),
                    SizedBox(
                      width: 145,
                      child: _metric(
                        Icons.explore_rounded,
                        'Wind direction',
                        formatValue(data, 'wind_direction_degrees', '°'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Weather time: ${data['weather_time'] ?? 'Unavailable'}',
                  style: const TextStyle(fontSize: 11, color: Colors.black54),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Source: Open-Meteo · Model-based current conditions',
                  style: TextStyle(fontSize: 10, color: Colors.black54),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // LEGEND
  // ---------------------------------------------------------------------------

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10, color: navy)),
      ],
    );
  }

  Widget _compactLegend() {
    final List<Widget> items;

    if (displayMode == 'Wind') {
      items = [
        _legendDot(const Color(0xFF42A5F5), '0–5'),
        _legendDot(const Color(0xFF26A69A), '5–15'),
        _legendDot(const Color(0xFFFFB300), '15–25'),
        _legendDot(const Color(0xFFEF5350), '25+ km/h'),
      ];
    } else if (displayMode == 'Temperature') {
      items = [
        _legendDot(const Color(0xFF42A5F5), '<20°'),
        _legendDot(const Color(0xFF26A69A), '20–25°'),
        _legendDot(const Color(0xFFFFB300), '25–30°'),
        _legendDot(const Color(0xFFEF5350), '30°+'),
      ];
    } else {
      items = [
        _legendDot(const Color(0xFF4CAF50), '<0.5 mm'),
        _legendDot(const Color(0xFFFFC107), '0.5–2'),
        _legendDot(const Color(0xFFFF7043), '2–5'),
        _legendDot(const Color(0xFF42A5F5), '5+ mm'),
      ];
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
      ),
      child: Wrap(spacing: 10, runSpacing: 6, children: items),
    );
  }

  // ---------------------------------------------------------------------------
  // MAP UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: navy,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: const LatLng(10.15, 76.35),
                initialZoom: 7.6,
                minZoom: 6.5,
                maxZoom: 15,
                onTap: (tapPosition, point) => _showPointDetails(point),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.example.kerala_climate_twin',
                  maxNativeZoom: 19,
                ),
                if (displayMode != 'Wind' && forecastGrid.isNotEmpty)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: ForecastHeatmapPainter(
                          points: forecastGrid,
                          camera: _mapController.camera,
                          isRainfall: displayMode == 'Rainfall',
                        ),
                      ),
                    ),
                  ),
                if (displayMode == 'Wind')
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _windAnimation,
                        builder: (context, _) => CustomPaint(
                          painter: WindParticlePainter(
                            progress: _windAnimation.value,
                            fallbackSpeedKmh: averageWindSpeed,
                            fallbackDirectionDegrees: averageWindDirection,
                            grid: windGrid,
                            camera: _mapController.camera,
                          ),
                        ),
                      ),
                    ),
                  ),
                MarkerLayer(
                  markers: climateLocations.map((location) {
                    final data = weatherData[location.name];

                    final value = displayMode == 'Temperature'
                        ? _forecastValue(data, 'temperature_2m')
                        : displayMode == 'Rainfall'
                        ? _forecastValue(data, 'precipitation')
                        : numericValue(data, 'wind_speed_kmh');

                    final color = displayMode == 'Wind'
                        ? windColor(value ?? 0)
                        : value == null
                        ? Colors.grey
                        : markerColor(value);

                    final selected = location.name == selectedDistrict;
                    final valueLabel = value == null
                        ? '--'
                        : displayMode == 'Temperature'
                        ? '${value.toStringAsFixed(0)}°'
                        : displayMode == 'Rainfall'
                        ? '${value.toStringAsFixed(1)} mm'
                        : '${value.toStringAsFixed(0)} km/h';
                    final conditionLabel = _conditionLabel(data);

                    return Marker(
                      point: LatLng(location.latitude, location.longitude),
                      width: 92,
                      height: 66,
                      alignment: Alignment.center,
                      child: GestureDetector(
                        onTap: () => selectLocation(location),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.96),
                                borderRadius: BorderRadius.circular(7),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFF5BE0B0)
                                      : Colors.white24,
                                  width: selected ? 1.5 : 0.6,
                                ),
                              ),
                              child: Text(
                                '$conditionLabel · $valueLabel',
                                maxLines: 1,
                                style: const TextStyle(
                                  color: Color(0xFF183A35),
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Container(
                              width: selected ? 22 : 16,
                              height: selected ? 22 : 16,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Colors.white,
                                  width: selected ? 3 : 2,
                                ),
                                boxShadow: const [
                                  BoxShadow(
                                    color: Colors.black38,
                                    blurRadius: 5,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('© OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
          ),

          // Map navigation actions.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _mapActionButton(
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
                    _mapActionButton(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reset map view',
                      onTap: () {
                        _mapController.move(const LatLng(10.15, 76.35), 7.6);
                        setState(() {
                          selectedDistrict = 'Kochi';
                          selectedForecastIndex = 0;
                          displayMode = 'Wind';
                          showLegend = true;
                        });
                        _lastForecastGridRequest = null;
                        scheduleForecastGridFetch(immediate: true);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: MediaQuery.of(context).padding.top + 62,
            left: 16,
            right: 16,
            child: Align(
              alignment: Alignment.center,
              child: _displayModeSelector(),
            ),
          ),

          // Floating map navigation controls.
          Positioned(
            right: 14,
            top: MediaQuery.of(context).size.height * 0.36,
            child: Column(
              children: [
                _mapActionButton(
                  icon: Icons.add_rounded,
                  tooltip: 'Zoom in',
                  onTap: () {
                    final camera = _mapController.camera;
                    _mapController.move(
                      camera.center,
                      (camera.zoom + 1).clamp(6, 15).toDouble(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _mapActionButton(
                  icon: Icons.remove_rounded,
                  tooltip: 'Zoom out',
                  onTap: () {
                    final camera = _mapController.camera;
                    _mapController.move(
                      camera.center,
                      (camera.zoom - 1).clamp(6, 15).toDouble(),
                    );
                  },
                ),
                const SizedBox(height: 8),
                _mapActionButton(
                  icon: Icons.my_location_rounded,
                  tooltip: 'Return to Kerala',
                  onTap: () {
                    _mapController.move(const LatLng(10.15, 76.35), 7.6);
                  },
                ),
              ],
            ),
          ),

          if (isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 150,
              right: 14,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: navy.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF5BE0B0),
                      ),
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Loading weather',
                      style: TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ),

          if (errorMessage != null && !isLoading)
            Positioned(
              top: MediaQuery.of(context).padding.top + 150,
              left: 14,
              right: 66,
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: navy.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  errorMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 11),
                ),
              ),
            ),

          // Forecast timeline, floating above the bottom of the map.
          if (displayMode != 'Wind' && _forecastLength > 0)
            Positioned(
              left: 12,
              right: 12,
              bottom: 16,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.fromLTRB(16, 13, 16, 11),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FBFA).withValues(alpha: 0.97),
                    borderRadius: BorderRadius.circular(23),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: emerald.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(11),
                            ),
                            child: Icon(
                              displayMode == 'Temperature'
                                  ? Icons.thermostat_rounded
                                  : Icons.water_drop_rounded,
                              color: emerald,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '$displayMode forecast',
                                  style: const TextStyle(
                                    color: navy,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  displayMode == 'Temperature'
                                      ? 'Degrees Celsius'
                                      : 'Precipitation in millimetres',
                                  style: const TextStyle(
                                    color: Colors.black54,
                                    fontSize: 10,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            _selectedForecastTime,
                            style: const TextStyle(
                              color: navy,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (isForecastGridLoading || forecastGridError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 7),
                          child: Row(
                            children: [
                              if (isForecastGridLoading)
                                const SizedBox(
                                  width: 11,
                                  height: 11,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    color: emerald,
                                  ),
                                )
                              else
                                const Icon(
                                  Icons.info_outline,
                                  size: 13,
                                  color: Colors.black54,
                                ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  isForecastGridLoading
                                      ? 'Updating map layer…'
                                      : forecastGridError!,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Colors.black54,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          activeTrackColor: emerald,
                          inactiveTrackColor: emerald.withValues(alpha: 0.18),
                          thumbColor: emerald,
                          overlayColor: emerald.withValues(alpha: 0.12),
                          trackHeight: 3,
                        ),
                        child: Slider(
                          min: 0,
                          max: (_forecastLength - 1).toDouble(),
                          divisions: _forecastLength > 1
                              ? _forecastLength - 1
                              : null,
                          value: selectedForecastIndex
                              .clamp(0, _forecastLength - 1)
                              .toDouble(),
                          onChanged: (value) {
                            setState(() {
                              selectedForecastIndex = value.round();
                            });
                            scheduleForecastGridFetch();
                          },
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'NOW',
                            style: TextStyle(
                              color: Colors.black45,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '${_forecastLength - 1} HOURS AHEAD',
                            style: const TextStyle(
                              color: Colors.black45,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (displayMode == 'Wind')
            Positioned(
              left: 14,
              right: 14,
              bottom: 20,
              child: SafeArea(
                top: false,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: navy.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(color: Colors.black26, blurRadius: 12),
                    ],
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.air_rounded,
                        color: Color(0xFF5BE0B0),
                        size: 24,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Wind conditions',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Average ${averageWindSpeed.toStringAsFixed(1)} km/h',
                              style: const TextStyle(
                                color: Color(0xFFB8C8D8),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: () => selectLocation(
                          climateLocations.firstWhere(
                            (location) => location.name == selectedDistrict,
                            orElse: () => climateLocations[6],
                          ),
                        ),
                        child: const Text(
                          'DETAILS',
                          style: TextStyle(
                            color: Color(0xFF5BE0B0),
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _displayModeSelector() {
    const modes = [
      (label: 'Wind', icon: Icons.air_rounded),
      (label: 'Temperature', icon: Icons.thermostat_rounded),
      (label: 'Rainfall', icon: Icons.water_drop_rounded),
    ];

    return Material(
      color: Colors.white.withValues(alpha: 0.96),
      elevation: 4,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: modes.map((mode) {
            final selected = displayMode == mode.label;

            return Semantics(
              button: true,
              selected: selected,
              label: '${mode.label} map layer',
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  if (displayMode == mode.label) return;
                  setState(() => displayMode = mode.label);
                  if (mode.label != 'Wind') {
                    scheduleForecastGridFetch(immediate: true);
                  }
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 11,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: selected ? emerald : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        mode.icon,
                        size: 16,
                        color: selected
                            ? Colors.white
                            : const Color(0xFF183A35),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        mode.label,
                        style: TextStyle(
                          color: selected
                              ? Colors.white
                              : const Color(0xFF183A35),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _mapActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      elevation: 3,
      shape: const CircleBorder(),
      child: Tooltip(
        message: tooltip,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(icon, color: const Color(0xFF183A35), size: 21),
          ),
        ),
      ),
    );
  }

  Widget _darkLegendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// TEMPERATURE / RAINFALL GRID OVERLAY
// -----------------------------------------------------------------------------

class _ProjectedForecastPoint {
  final double x;
  final double y;
  final double value;

  const _ProjectedForecastPoint(this.x, this.y, this.value);
}

class ForecastHeatmapPainter extends CustomPainter {
  final List<ForecastGridPoint> points;
  final MapCamera camera;
  final bool isRainfall;

  ForecastHeatmapPainter({
    required this.points,
    required this.camera,
    required this.isRainfall,
  });

  // Blend between nearby stops instead of using hard thresholds. This makes
  // the forecast field look continuous rather than like blocks of square cells.
  Color _colorFor(double value) {
    final stops = isRainfall
        ? <(double, Color)>[
            (0.0, const Color(0x554CAF50)),
            (0.5, const Color(0x7797D83D)),
            (2.0, const Color(0x88FFD54F)),
            (5.0, const Color(0x99FF7043)),
            (10.0, const Color(0xAA42A5F5)),
          ]
        : <(double, Color)>[
            (15.0, const Color(0x8842A5F5)),
            (20.0, const Color(0x8826C6DA)),
            (25.0, const Color(0x9926A69A)),
            (30.0, const Color(0x99FFB300)),
            (35.0, const Color(0xAAEF5350)),
          ];

    if (value <= stops.first.$1) return stops.first.$2;
    if (value >= stops.last.$1) return stops.last.$2;

    for (var i = 0; i < stops.length - 1; i++) {
      final lower = stops[i];
      final upper = stops[i + 1];
      if (value >= lower.$1 && value <= upper.$1) {
        final t = ((value - lower.$1) / (upper.$1 - lower.$1))
            .clamp(0.0, 1.0)
            .toDouble();
        return Color.lerp(lower.$2, upper.$2, t) ?? lower.$2;
      }
    }
    return stops.last.$2;
  }

  // Approximate Kerala outline in geographic coordinates. This keeps most of
  // the colour field on Kerala rather than covering the whole bounding box.
  bool _insideKerala(double lat, double lon) {
    const outline = <LatLng>[
      LatLng(8.15, 77.00),
      LatLng(8.45, 76.70),
      LatLng(8.90, 76.55),
      LatLng(9.30, 76.35),
      LatLng(9.70, 76.20),
      LatLng(10.10, 76.15),
      LatLng(10.50, 75.95),
      LatLng(10.90, 75.85),
      LatLng(11.30, 75.75),
      LatLng(11.70, 75.50),
      LatLng(12.00, 75.15),
      LatLng(12.55, 74.85),
      LatLng(12.55, 75.55),
      LatLng(12.15, 75.85),
      LatLng(11.85, 76.20),
      LatLng(11.45, 76.45),
      LatLng(11.00, 76.65),
      LatLng(10.55, 76.95),
      LatLng(10.10, 77.15),
      LatLng(9.60, 77.25),
      LatLng(9.10, 77.15),
      LatLng(8.60, 77.20),
    ];

    var inside = false;
    for (int i = 0, j = outline.length - 1; i < outline.length; j = i++) {
      final yi = outline[i].latitude;
      final xi = outline[i].longitude;
      final yj = outline[j].latitude;
      final xj = outline[j].longitude;

      final crosses =
          ((yi > lat) != (yj > lat)) &&
          (lon <
              (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 0.000001 : (yj - yi)) +
                  xi);
      if (crosses) inside = !inside;
    }
    return inside;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || points.length < 3) return;

    final projected = <_ProjectedForecastPoint>[];
    for (final point in points) {
      final screen = camera.latLngToScreenOffset(
        LatLng(point.latitude, point.longitude),
      );
      projected.add(_ProjectedForecastPoint(screen.dx, screen.dy, point.value));
    }

    // Paint a modest-resolution interpolated field to keep rendering smooth.
    const cellSize = 7.0;
    final paint = Paint()..style = PaintingStyle.fill;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    for (double y = 0; y < size.height; y += cellSize) {
      for (double x = 0; x < size.width; x += cellSize) {
        final geo = camera.screenOffsetToLatLng(
          Offset(x + cellSize / 2, y + cellSize / 2),
        );
        if (!_insideKerala(geo.latitude, geo.longitude)) continue;

        final nearby =
            projected.map((point) {
                final dx = point.x - (x + cellSize / 2);
                final dy = point.y - (y + cellSize / 2);
                return (point: point, distanceSquared: dx * dx + dy * dy);
              }).toList()
              ..sort((a, b) => a.distanceSquared.compareTo(b.distanceSquared));

        double weighted = 0;
        double totalWeight = 0;
        final count = math.min(4, nearby.length);
        for (int i = 0; i < count; i++) {
          final item = nearby[i];
          if (item.distanceSquared < 0.001) {
            weighted = item.point.value;
            totalWeight = 1;
            break;
          }
          final weight = 1 / item.distanceSquared;
          weighted += item.point.value * weight;
          totalWeight += weight;
        }

        if (totalWeight > 0) {
          final value = weighted / totalWeight;
          paint.color = _colorFor(value);
          canvas.drawRect(
            Rect.fromLTWH(x, y, cellSize + 1, cellSize + 1),
            paint,
          );
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant ForecastHeatmapPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.camera != camera ||
        oldDelegate.isRainfall != isRainfall;
  }
}

// -----------------------------------------------------------------------------
// WIND PARTICLE PAINTER
// -----------------------------------------------------------------------------

Color windColor(double speed) {
  if (speed < 5) return const Color(0xFF42A5F5);
  if (speed < 15) return const Color(0xFF26A69A);
  if (speed < 25) return const Color(0xFFFFB300);
  return const Color(0xFFEF5350);
}

class _ProjectedWindPoint {
  final double x;
  final double y;
  final double u;
  final double v;

  const _ProjectedWindPoint({
    required this.x,
    required this.y,
    required this.u,
    required this.v,
  });
}

class WindParticlePainter extends CustomPainter {
  final double progress;
  final double fallbackSpeedKmh;
  final double fallbackDirectionDegrees;
  final List<WindGridPoint> grid;
  final MapCamera camera;

  WindParticlePainter({
    required this.progress,
    required this.fallbackSpeedKmh,
    required this.fallbackDirectionDegrees,
    required this.grid,
    required this.camera,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    const particleCount = 125;
    const stepSize = 3.0;

    // Convert geographic wind-grid locations to map-screen offsets.
    final projected = <_ProjectedWindPoint>[];

    for (final point in grid) {
      final screen = camera.latLngToScreenOffset(
        LatLng(point.latitude, point.longitude),
      );

      projected.add(
        _ProjectedWindPoint(
          x: screen.dx,
          y: screen.dy,
          u: point.uKmh,
          v: point.vKmh,
        ),
      );
    }

    // Meteorological direction means the direction wind comes FROM.
    final direction = fallbackDirectionDegrees * math.pi / 180;
    final fallbackU = -fallbackSpeedKmh * math.sin(direction);
    final fallbackV = -fallbackSpeedKmh * math.cos(direction);

    for (int i = 0; i < particleCount; i++) {
      final seedX = _pseudoRandom(i * 17 + 3);
      final seedY = _pseudoRandom(i * 31 + 11);

      // Phase moves the particle along its local wind trajectory.
      final phase = (progress + seedY) % 1.0;

      final startX = seedX * size.width;
      final startY = seedY * size.height;

      var x = startX;
      var y = startY;

      final trail = <Offset>[Offset(x, y)];
      double localSpeed = fallbackSpeedKmh;

      // Integrate the local vector field in small steps.
      // This allows the trail direction to change across the map.
      final travelDistance = phase * 28.0;
      final integrationSteps = (travelDistance / stepSize).ceil();

      for (int step = 0; step < integrationSteps; step++) {
        final vector = _interpolateVector(
          x,
          y,
          projected,
          fallbackU,
          fallbackV,
        );

        final u = vector.$1;
        final v = vector.$2;

        localSpeed = math.sqrt(u * u + v * v);

        if (localSpeed < 0.1) break;

        // u is eastward; v is northward.
        // Screen y increases downwards, so invert v.
        final dx = u / localSpeed;
        final dy = -v / localSpeed;

        final remaining = travelDistance - step * stepSize;
        final distance = math.min(stepSize, remaining);

        x += dx * distance;
        y += dy * distance;

        // Stop at screen edges instead of wrapping. Wrapping a trail from
        // one edge to the opposite edge creates distracting horizontal lines.
        if (x < 0 || x >= size.width || y < 0 || y >= size.height) {
          break;
        }

        trail.add(Offset(x, y));
      }

      final speedFactor = (localSpeed / 15.0).clamp(0.25, 2.0).toDouble();

      final color = windColor(localSpeed);
      final alpha = 0.38 + 0.58 * (1.0 - phase);

      // Draw a fading trail.
      for (int j = 0; j < trail.length - 1; j++) {
        final p1 = trail[j];
        final p2 = trail[j + 1];
        final fade = 1.0 - j / trail.length;

        final paint = Paint()
          ..color = color.withValues(alpha: alpha * fade)
          ..strokeWidth = 1.0 + speedFactor * 0.4
          ..strokeCap = StrokeCap.round;

        canvas.drawLine(p1, p2, paint);
      }

      // Draw the moving particle head.
      canvas.drawCircle(
        Offset(x, y),
        1.2 + speedFactor * 0.3,
        Paint()..color = color.withValues(alpha: 0.85),
      );
    }
  }

  // Inverse-distance interpolation from the four nearest grid points.
  (double, double) _interpolateVector(
    double x,
    double y,
    List<_ProjectedWindPoint> points,
    double fallbackU,
    double fallbackV,
  ) {
    if (points.isEmpty) {
      return (fallbackU, fallbackV);
    }

    final nearby = points.map((point) {
      final dx = point.x - x;
      final dy = point.y - y;

      return (point: point, distanceSquared: dx * dx + dy * dy);
    }).toList()..sort((a, b) => a.distanceSquared.compareTo(b.distanceSquared));

    final count = math.min(4, nearby.length);

    double weightedU = 0.0;
    double weightedV = 0.0;
    double totalWeight = 0.0;

    for (int i = 0; i < count; i++) {
      final item = nearby[i];

      // Avoid division by zero if the sample is exactly at the point.
      if (item.distanceSquared < 0.001) {
        return (item.point.u, item.point.v);
      }

      final weight = 1.0 / item.distanceSquared;

      weightedU += item.point.u * weight;
      weightedV += item.point.v * weight;
      totalWeight += weight;
    }

    if (totalWeight == 0.0) {
      return (fallbackU, fallbackV);
    }

    return (weightedU / totalWeight, weightedV / totalWeight);
  }

  double _pseudoRandom(int value) {
    final x = math.sin(value * 12.9898) * 43758.5453;
    return x - x.floorToDouble();
  }

  @override
  bool shouldRepaint(covariant WindParticlePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.fallbackSpeedKmh != fallbackSpeedKmh ||
        oldDelegate.fallbackDirectionDegrees != fallbackDirectionDegrees ||
        oldDelegate.grid != grid ||
        oldDelegate.camera != camera;
  }
}
