import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _green = Color(0xFF087E75);
const _navy = Color(0xFF102A43);
const _muted = Color(0xFF627D98);
const String _apiBaseUrl = 'https://mp-cjn5.onrender.com';

class SmartAgricultureScreen extends StatefulWidget {
  final String initialDistrict;
  final List<String> districts;

  const SmartAgricultureScreen({
    super.key,
    required this.initialDistrict,
    required this.districts,
  });

  @override
  State<SmartAgricultureScreen> createState() => _SmartAgricultureScreenState();
}

class _SmartAgricultureScreenState extends State<SmartAgricultureScreen> {
  late String district;
  String crop = 'Rice';
  String cropStage = 'Planning / planting';
  Map<String, dynamic>? weather;
  bool loading = true;
  String? error;

  static const crops = [
    'Rice',
    'Banana',
    'Tapioca',
    'Black pepper',
    'Vegetables',
  ];
  static const stages = [
    'Planning / planting',
    'Growing',
    'Flowering / fruiting',
  ];

  @override
  void initState() {
    super.initState();
    district = widget.initialDistrict;
    loadForecast();
  }

  Future<void> loadForecast() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await http
          .get(
            Uri.parse(
              '$_apiBaseUrl/api/weather/${Uri.encodeComponent(district)}',
            ),
          )
          .timeout(const Duration(seconds: 25));
      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Invalid weather response');
      }
      if (!mounted) return;
      setState(() {
        weather = decoded;
        loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        loading = false;
        error = 'Could not load the forecast. Check the backend connection.';
      });
    }
  }

  Map<String, List<dynamic>> get hourly {
    final raw = weather?['hourly'];
    if (raw is! Map) return {};
    return raw.map(
      (key, value) =>
          MapEntry(key.toString(), value is List ? value : <dynamic>[]),
    );
  }

  List<double> _numbers(List<dynamic>? values, {int limit = 168}) {
    if (values == null) return [];
    return values
        .take(limit)
        .whereType<num>()
        .map((v) => v.toDouble())
        .where((v) => v.isFinite)
        .toList();
  }

  double? _mean(String key) {
    final values = _numbers(hourly[key]);
    if (values.isEmpty) return null;
    return values.reduce((a, b) => a + b) / values.length;
  }

  double? _rainTotal() {
    final values = _numbers(hourly['precipitation']);
    if (values.isEmpty) return null;
    return values.fold<double>(0, (sum, v) => sum + v);
  }

  double? _maxRainDay() {
    final times = hourly['time'];
    final rain = hourly['precipitation'];
    if (times == null || rain == null || times.isEmpty || rain.isEmpty)
      return null;
    final totals = <String, double>{};
    final length = times.length < rain.length ? times.length : rain.length;
    for (var i = 0; i < length && i < 168; i++) {
      final day = times[i].toString().split('T').first;
      final value = rain[i];
      if (value is num && value.isFinite)
        totals[day] = (totals[day] ?? 0) + value.toDouble();
    }
    if (totals.isEmpty) return null;
    return totals.values.reduce((a, b) => a > b ? a : b);
  }

  double? _currentNumber(String key) {
    final value = weather?[key];
    return value is num ? value.toDouble() : null;
  }

  ({bool canFarm, String title, String detail, Color color})
  get currentFarmability {
    final temp = _currentNumber('temperature_c');
    final rain = _currentNumber('precipitation_mm');
    final wind = _currentNumber('wind_speed_kmh');
    final weatherCode = _currentNumber('weather_code');

    if (temp == null || rain == null || wind == null || weatherCode == null) {
      return (
        canFarm: false,
        title: 'Cannot assess right now',
        detail: 'Current weather data is incomplete. Refresh before making a farm decision.',
        color: const Color(0xFF8A5A00),
      );
    }

    final ranges = <String, (double min, double max)>{
      'Rice': (20, 35),
      'Banana': (18, 35),
      'Tapioca': (20, 35),
      'Black pepper': (20, 32),
      'Vegetables': (15, 30),
    };
    final range = ranges[crop]!;
    final temperatureOk = temp >= range.$1 && temp <= range.$2;
    final rainOk = rain <= 8;
    final windOk = wind <= 35;
    final severeWeather = weatherCode >= 95;
    final canFarm = temperatureOk && rainOk && windOk && !severeWeather;

    if (canFarm) {
      return (
        canFarm: true,
        title: 'Can be farmed now',
        detail:
            '$crop is within the preferred temperature range and current conditions are workable.',
        color: _green,
      );
    }

    final reasons = <String>[];
    if (!temperatureOk) {
      reasons.add(
        '${temp.toStringAsFixed(1)}°C is outside the '
        '${range.$1.toStringAsFixed(0)}–${range.$2.toStringAsFixed(0)}°C range',
      );
    }
    if (!rainOk) reasons.add('current rain is ${rain.toStringAsFixed(1)} mm');
    if (!windOk) reasons.add('wind is ${wind.toStringAsFixed(1)} km/h');
    if (severeWeather) reasons.add('severe weather is reported');

    return (
      canFarm: false,
      title: 'Do not farm now',
      detail: '${reasons.join('; ')}. Wait for safer conditions and reassess.',
      color: const Color(0xFFB42318),
    );
  }

  String get plantingAdvice {
    final temp = _mean('temperature_2m') ?? _mean('temperature');
    final rain = _rainTotal();
    if (temp == null || rain == null) {
      return 'Not enough forecast data to assess planting conditions. Check a local agricultural advisory before deciding.';
    }
    if (rain >= 100) {
      return 'Consider waiting and checking field drainage. The forecast indicates substantial rain over the available forecast period, which may increase waterlogging risk.';
    }
    if (temp < 15 || temp > 38) {
      return 'Temperature may be stressful for some crops. Check the selected crop variety and local agricultural guidance before planting.';
    }
    if (crop == 'Rice' && rain >= 20 && rain < 100) {
      return 'Rain may support field preparation for some rice systems, but planting suitability depends on the rice variety, water control, soil, and local season.';
    }
    if (rain < 5) {
      return 'Little rain is forecast over the available period. Check soil moisture and irrigation access before planting.';
    }
    return 'Weather indicators do not show an obvious extreme in this forecast window, but this is not a crop-specific guarantee. Check soil moisture, drainage, season, and local agricultural guidance.';
  }

  String get suitabilityLabel {
    final rain = _rainTotal();
    final temp = _mean('temperature_2m') ?? _mean('temperature');
    if (rain == null || temp == null) return 'Insufficient data';
    if (rain >= 100 || temp < 15 || temp > 38) return 'Use caution';
    return 'Review conditions';
  }

  @override
  Widget build(BuildContext context) {
    final temp = _mean('temperature_2m') ?? _mean('temperature');
    final humidity = _mean('relative_humidity_2m') ?? _mean('humidity');
    final rain = _rainTotal();
    final peakRain = _maxRainDay();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _navy,
        elevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        title: const Text(
          'Smart Agriculture',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: loading ? null : loadForecast,
            tooltip: 'Refresh forecast',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: loadForecast,
        color: _green,
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            const Text(
              'Forecast-based crop guidance',
              style: TextStyle(color: _muted),
            ),
            const SizedBox(height: 16),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'YOUR FARM CONDITIONS',
                    style: TextStyle(
                      color: _green,
                      fontSize: 11,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    value: district,
                    decoration: const InputDecoration(
                      labelText: 'District / city',
                      prefixIcon: Icon(Icons.location_on_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: widget.districts
                        .map((d) => DropdownMenuItem(value: d, child: Text(d)))
                        .toList(),
                    onChanged: (value) {
                      if (value == null || value == district) return;
                      setState(() {
                        district = value;
                        weather = null;
                      });
                      loadForecast();
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: crop,
                    decoration: const InputDecoration(
                      labelText: 'Crop',
                      prefixIcon: Icon(Icons.grass_outlined),
                      border: OutlineInputBorder(),
                    ),
                    items: crops
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                    onChanged: (value) => setState(() => crop = value ?? crop),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: cropStage,
                    decoration: const InputDecoration(
                      labelText: 'Crop stage',
                      prefixIcon: Icon(Icons.timeline_rounded),
                      border: OutlineInputBorder(),
                    ),
                    items: stages
                        .map((s) => DropdownMenuItem(value: s, child: Text(s)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => cropStage = value ?? cropStage),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _currentFarmabilityCard(),
            const SizedBox(height: 14),
            if (loading) const LinearProgressIndicator(color: _green),
            if (error != null) ...[
              const SizedBox(height: 12),
              _panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(error!, style: const TextStyle(color: Colors.red)),
                    TextButton.icon(
                      onPressed: loadForecast,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDDF4E7),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(
                          Icons.eco_rounded,
                          color: _green,
                          size: 27,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Planting outlook',
                              style: TextStyle(
                                fontSize: 18,
                                color: _navy,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(height: 3),
                            Text(
                              'Based on available forecast values',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3D6),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          suitabilityLabel,
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF8A5A00),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    plantingAdvice,
                    style: const TextStyle(color: _navy, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Crop: $crop · Stage: $cropStage',
                    style: const TextStyle(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Next 7 days · available forecast',
              style: TextStyle(
                fontSize: 19,
                color: _navy,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    'Rain total',
                    rain == null ? '--' : '${rain.toStringAsFixed(1)} mm',
                    Icons.water_drop_outlined,
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    'Avg. temperature',
                    temp == null ? '--' : '${temp.toStringAsFixed(1)} °C',
                    Icons.thermostat_outlined,
                    Colors.deepOrange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _metric(
                    'Avg. humidity',
                    humidity == null ? '--' : '${humidity.toStringAsFixed(0)}%',
                    Icons.opacity_rounded,
                    _green,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _metric(
                    'Wettest day',
                    peakRain == null
                        ? '--'
                        : '${peakRain.toStringAsFixed(1)} mm',
                    Icons.cloudy_snowing,
                    Colors.indigo,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Farm action checklist',
                    style: TextStyle(
                      color: _navy,
                      fontWeight: FontWeight.bold,
                      fontSize: 17,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _check('Check soil moisture before irrigation.'),
                  _check('Inspect field drainage if heavy rain is forecast.'),
                  _check(
                    'Watch for crop-specific disease symptoms during prolonged wet weather.',
                  ),
                  _check(
                    'Confirm planting dates with local Krishi Bhavan / agricultural guidance.',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _panel(
              child: const Text(
                'Important: this screen summarizes general weather indicators, not a validated agronomy model. Crop-specific planting decisions also depend on variety, soil type, field drainage, season, pests, and local recommendations. Forecast data can be incomplete; no values are invented when data is missing.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _panel({required Widget child}) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFD9E3EA)),
    ),
    child: child,
  );

  Widget _currentFarmabilityCard() {
    final assessment = currentFarmability;
    final temp = _currentNumber('temperature_c');
    final rain = _currentNumber('precipitation_mm');
    final wind = _currentNumber('wind_speed_kmh');

    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'CAN YOU FARM THIS CROP NOW?',
            style: TextStyle(
              color: _green,
              fontSize: 11,
              letterSpacing: 1.1,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(
                assessment.canFarm
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: assessment.color,
                size: 30,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  assessment.title,
                  style: TextStyle(
                    color: assessment.color,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assessment.detail,
            style: const TextStyle(color: _navy, height: 1.45),
          ),
          if (temp != null && rain != null && wind != null) ...[
            const SizedBox(height: 12),
            Text(
              'Current: ${temp.toStringAsFixed(1)}°C · '
              '${rain.toStringAsFixed(1)} mm rain · '
              '${wind.toStringAsFixed(1)} km/h wind',
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }

  Widget _metric(String label, String value, IconData icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFFD9E3EA)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 12),
            Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 5),
            Text(
              value,
              style: const TextStyle(
                color: _navy,
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
          ],
        ),
      );

  Widget _check(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, color: _green, size: 19),
        const SizedBox(width: 9),
        Expanded(
          child: Text(text, style: const TextStyle(color: _navy, height: 1.4)),
        ),
      ],
    ),
  );
}
