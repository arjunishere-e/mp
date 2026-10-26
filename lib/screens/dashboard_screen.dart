
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

import 'data_sources_screen.dart';
import 'map_screen.dart';
import 'historical_analysis_screen.dart';
import 'smart_agriculture_screen.dart';
import '../services/device_location_service.dart';

const climateGreen = Color(0xFF087E75);
const climateNavy = Color(0xFF102A43);
const climateMuted = Color(0xFF627D98);

const String apiBaseUrl = 'https://mp-cjn5.onrender.com';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int selectedIndex = 0;
  String? district;
  Map<String, dynamic>? weather;
  bool isLoading = false;
  bool isLocating = true;
  String? errorMessage;

  final List<String> districts = [
    'Kochi',
    'Thiruvananthapuram',
    'Kozhikode',
    'Thrissur',
    'Kottayam',
    'Alappuzha',
    'Palakkad',
    'Kannur',
    'Wayanad',
    'Kasaragod',
    'Malappuram',
    'Kollam',
    'Pathanamthitta',
    'Idukki',
  ];

  @override
  void initState() {
    super.initState();
    _loadWeatherForCurrentLocation();
  }

  Future<void> _loadWeatherForCurrentLocation() async {
    if (mounted) {
      setState(() {
        isLocating = true;
        errorMessage = null;
      });
    }

    final position = await DeviceLocationService.currentPosition();
    if (!mounted) return;

    if (position == null) {
      setState(() {
        isLocating = false;
        errorMessage =
            'Turn on location permission and services to detect your district automatically.';
      });
      return;
    }

    final nearest = _nearestDistrict(
      position.latitude,
      position.longitude,
    );
    setState(() {
      district = nearest;
      isLocating = false;
    });
    await fetchWeather();
  }

  String _nearestDistrict(double latitude, double longitude) {
    var nearest = districts.first;
    var nearestDistance = double.infinity;

    const coordinates = <String, (double, double)>{
      'Thiruvananthapuram': (8.5241, 76.9366),
      'Kollam': (8.8932, 76.6141),
      'Pathanamthitta': (9.2648, 76.7870),
      'Alappuzha': (9.4981, 76.3388),
      'Kottayam': (9.5916, 76.5222),
      'Idukki': (9.8494, 76.9720),
      'Kochi': (9.9312, 76.2673),
      'Thrissur': (10.5276, 76.2144),
      'Palakkad': (10.7867, 76.6548),
      'Malappuram': (11.0510, 76.0711),
      'Kozhikode': (11.2588, 75.7804),
      'Wayanad': (11.6854, 76.1320),
      'Kannur': (11.8745, 75.3704),
      'Kasaragod': (12.4996, 74.9869),
    };

    for (final entry in coordinates.entries) {
      final distance = (entry.value.$1 - latitude) * (entry.value.$1 - latitude) +
          (entry.value.$2 - longitude) * (entry.value.$2 - longitude);
      if (distance < nearestDistance) {
        nearest = entry.key;
        nearestDistance = distance;
      }
    }
    return nearest;
  }

  Future<void> fetchWeather() async {
    final selectedDistrict = district;
    if (selectedDistrict == null) return;

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final uri = Uri.parse(
        '$apiBaseUrl/api/weather/${Uri.encodeComponent(selectedDistrict)}',
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 25));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(response.body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid API response');
      }

      if (!mounted) return;

      setState(() {
        weather = decoded;
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        isLoading = false;
        errorMessage =
            'Could not fetch weather. Check your backend connection.';
      });
    }
  }

  String displayValue(String key, String unit) {
    final value = weather?[key];

    if (value is! num) return '-- $unit';

    return '${value.toString()} $unit';
  }

  String get weatherTime {
    final value = weather?['weather_time'];

    if (value == null) return 'Not available';

    return value.toString().replaceFirst('T', ' ');
  }


  // Sum hourly precipitation values for each local date in the API response.
  Map<String, double> _dailyRainfallTotals() {
    final hourly = weather?['hourly'];

    if (hourly is! Map) return {};

    final times = hourly['time'];
    final rainfall = hourly['precipitation'];

    if (times is! List || rainfall is! List) return {};

    final totals = <String, double>{};

    for (int i = 0; i < times.length && i < rainfall.length; i++) {
      final timestamp = times[i].toString();
      final day = timestamp.split('T').first;
      final value = rainfall[i];

      if (value is num && value.isFinite) {
        totals[day] = (totals[day] ?? 0) + value.toDouble();
      }
    }

    return totals;
  }

  // Convert hourly API values into chart points.
  List<FlSpot> _chartPoints(String key) {
    final hourly = weather?['hourly'];

    if (hourly is! Map<String, dynamic>) {
      return [];
    }

    final values = hourly[key];

    if (values is! List) {
      return [];
    }

    final points = <FlSpot>[];

    for (int i = 0; i < values.length; i++) {
      final value = values[i];

      if (value is num && value.isFinite) {
        points.add(
          FlSpot(i.toDouble(), value.toDouble()),
        );
      }
    }

    return points;
  }

  // Build a reusable weather line chart.
  Widget _buildWeatherChart({
    required String title,
    required String variable,
    required String unit,
    required Color lineColor,
  }) {
    final points = _chartPoints(variable);

    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD9E3EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: climateNavy,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Hourly values · $unit',
            style: const TextStyle(
              color: climateMuted,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 18),

          if (isLoading && points.isEmpty)
            const SizedBox(
              height: 180,
              child: Center(
                child: CircularProgressIndicator(
                  color: climateGreen,
                ),
              ),
            )
          else if (points.isEmpty)
            const SizedBox(
              height: 120,
              child: Center(
                child: Text('Hourly data is not available'),
              ),
            )
          else
            SizedBox(
              height: 210,
              child: LineChart(
                LineChartData(
                  minX: points.first.x,
                  maxX: points.last.x > points.first.x
                      ? points.last.x
                      : points.first.x + 1,
                  gridData: const FlGridData(show: true),
                  borderData: FlBorderData(show: false),
                  titlesData: FlTitlesData(
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                      ),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: false,
                      ),
                    ),
                   bottomTitles: AxisTitles(
  axisNameWidget: const Text(
    'Time (IST)',
    style: TextStyle(fontSize: 10),
  ),
  sideTitles: SideTitles(
    showTitles: true,
    reservedSize: 30,
    interval: 6,
    getTitlesWidget: (value, meta) {
      final hourly = weather?['hourly'];
      final times = hourly is Map
          ? hourly['time']
          : null;

      final index = value.toInt();

      if (times is! List ||
          index < 0 ||
          index >= times.length) {
        return const SizedBox.shrink();
      }

      final timestamp = times[index].toString();
      final timePart = timestamp.contains('T')
          ? timestamp.split('T').last
          : timestamp;

      return SideTitleWidget(
        meta: meta,
        child: Text(
          timePart.length >= 5
              ? timePart.substring(0, 5)
              : timePart,
          style: const TextStyle(fontSize: 10),
        ),
      );
    },
  ),
),
                    leftTitles: const AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 42,
                      ),
                    ),
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: points,
                      isCurved: true,
                      color: lineColor,
                      barWidth: 2.5,
                      dotData: const FlDotData(
                        show: false,
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        color: lineColor.withValues(
                          alpha: 0.12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // MapScreen is deliberately NOT embedded in this page list.
    // It is opened as a separate route so this Scaffold's AppBar and
    // NavigationBar are not shown behind the map.
    final pages = <Widget>[
      _buildOverview(),
      _buildOverview(), // Map opens as its own route; this slot is never selected.
      const DataSourcesScreen(),
      const HistoricalAnalysisScreen(),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Climate Twin',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: isLoading ? null : fetchWeather,
            tooltip: 'Refresh weather',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: pages[selectedIndex],
      ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    const destinations = [
      (icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard, label: 'Overview'),
      (icon: Icons.map_outlined, selectedIcon: Icons.map, label: 'Map'),
      (icon: Icons.storage_outlined, selectedIcon: Icons.storage, label: 'Data Sources'),
      (icon: Icons.analytics_outlined, selectedIcon: Icons.analytics, label: 'Analysis'),
    ];

    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(28, 0, 28, 14),
      child: Container(
        height: 66,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF202629),
          borderRadius: BorderRadius.circular(34),
          boxShadow: const [
            BoxShadow(
              color: Color(0x30000000),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: destinations.asMap().entries.map((entry) {
            final index = entry.key;
            final destination = entry.value;
            final selected = selectedIndex == index;

            return Tooltip(
              message: destination.label,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () {
                  if (index == 1) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const MapScreen(),
                        settings: const RouteSettings(name: '/climate-map'),
                      ),
                    );
                    return;
                  }
                  setState(() => selectedIndex = index);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: selected ? 52 : 44,
                  height: 50,
                  decoration: BoxDecoration(
                    color: selected ? Colors.white : Colors.transparent,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    selected ? destination.selectedIcon : destination.icon,
                    color: selected
                        ? const Color(0xFF202629)
                        : Colors.white.withValues(alpha: 0.88),
                    size: 23,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildOverview() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'KERALA CLIMATE MONITOR',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: climateGreen,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Climate overview',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: climateNavy,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Explore climate indicators across Kerala.',
          style: TextStyle(color: climateMuted),
        ),
        const SizedBox(height: 20),

        DropdownButtonFormField<String>(
          initialValue: district,
          hint: Text(isLocating ? 'Detecting current district…' : 'Select a district'),
          decoration: const InputDecoration(
            labelText: 'Select district / city',
            prefixIcon: Icon(
              Icons.location_on_outlined,
            ),
          ),
          items: districts.map((name) {
            return DropdownMenuItem<String>(
              value: name,
              child: Text(name),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null && value != district) {
              setState(() {
                district = value;
                weather = null;
              });

              fetchWeather();
            }
          },
        ),

        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: climateNavy,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'SELECTED LOCATION',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 11,
                  letterSpacing: 1.3,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                district ?? 'Current location unavailable',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isLoading
                    ? 'Fetching weather data...'
                    : 'Weather data from Open-Meteo',
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 20),
              const Row(
                children: [
                  Icon(
                    Icons.cloud_outlined,
                    color: Colors.white,
                    size: 34,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Live API connection',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        const Text(
          'Climate indicators',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: climateNavy,
          ),
        ),
        const SizedBox(height: 12),

        if (isLoading) ...[
          const LinearProgressIndicator(
            color: climateGreen,
          ),
          const SizedBox(height: 12),
        ],

        if (errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  errorMessage!,
                  style: TextStyle(
                    color: Colors.red.shade800,
                  ),
                ),
                TextButton.icon(
                  onPressed: fetchWeather,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],

        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Temperature',
                value: displayValue('temperature_c', '°C'),
                icon: Icons.thermostat,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Precipitation',
                value: displayValue('precipitation_mm', 'mm'),
                icon: Icons.water_drop_outlined,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _MetricCard(
                title: 'Humidity',
                value: displayValue('humidity_percent', '%'),
                icon: Icons.opacity,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _MetricCard(
                title: 'Wind speed',
                value: displayValue('wind_speed_kmh', 'km/h'),
                icon: Icons.air,
              ),
            ),
          ],
        ),

        const SizedBox(height: 22),

        // Dedicated entry point for forecast-based agricultural guidance.
        _buildSmartAgricultureTile(),

        // STEP 3: The charts are inserted here, after the metrics.
        const SizedBox(height: 24),

        const Text(
          'Weather trends',
          style: TextStyle(
            fontSize: 21,
            fontWeight: FontWeight.bold,
            color: climateNavy,
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Hourly weather values for the selected location.',
          style: TextStyle(color: climateMuted),
        ),
        const SizedBox(height: 14),

        _buildWeatherChart(
          title: 'Temperature',
          variable: 'temperature_2m',
          unit: '°C',
          lineColor: climateGreen,
        ),

        _buildWeatherChart(
          title: 'Hourly precipitation',
          variable: 'precipitation',
          unit: 'mm',
          lineColor: Colors.blue,
        ),

        const SizedBox(height: 8),

        const Text(
          'Daily rainfall totals',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: climateNavy,
          ),
        ),
        const SizedBox(height: 12),

        if (_dailyRainfallTotals().isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Daily rainfall data is not available yet.',
              style: TextStyle(color: climateMuted),
            ),
          )
        else
          ..._dailyRainfallTotals().entries.map(
            (entry) => Card(
              color: Colors.white,
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: const BorderSide(color: Color(0xFFD9E3EA)),
              ),
              child: ListTile(
                leading: const Icon(
                  Icons.water_drop_outlined,
                  color: climateGreen,
                ),
                title: Text(entry.key),
                subtitle: const Text('Sum of hourly forecast precipitation'),
                trailing: Text(
                  '${entry.value.toStringAsFixed(1)} mm',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: climateNavy,
                  ),
                ),
              ),
            ),
          ),

        const SizedBox(height: 8),

        // Data source and timestamp information.
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: const Color(0xFFD9E3EA),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DATA PROVENANCE',
                style: TextStyle(
                  color: climateGreen,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              _infoRow(
                'Source',
                weather?['source']?.toString() ?? '—',
              ),
              _infoRow('Weather time', weatherTime),
              _infoRow(
                'Last fetched',
                weather?['fetched_at']?.toString() ?? '—',
              ),
              _infoRow(
                'Cloud cover',
                displayValue('cloud_cover_percent', '%'),
              ),
              _infoRow(
                'Status',
                errorMessage != null
                    ? 'Connection error'
                    : isLoading
                        ? 'Fetching'
                        : weather != null
                            ? 'Connected'
                            : 'Waiting',
              ),
              const SizedBox(height: 8),
              const Text(
                'Values are model-based weather estimates, not '
                'necessarily direct measurements from a local '
                'weather station. Precipitation shown above is '
                'the API hourly value, not a daily total.',
                style: TextStyle(
                  fontSize: 12,
                  color: climateMuted,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 20),

        const Text(
          'Module 1 · Data Acquisition',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: climateNavy,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Explore the sources used in the climate data pipeline.',
          style: TextStyle(color: climateMuted),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: () {
            setState(() => selectedIndex = 2);
          },
          icon: const Icon(Icons.storage),
          label: const Text('Explore data sources'),
          style: FilledButton.styleFrom(
            backgroundColor: climateGreen,
            padding: const EdgeInsets.all(16),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartAgricultureTile() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => SmartAgricultureScreen(
                initialDistrict: district ?? districts.first,
                districts: districts,
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFD9E3EA)),
            gradient: const LinearGradient(
              colors: [Color(0xFFF0FAF5), Colors.white],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: const Color(0xFFDDF4E7),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.agriculture_rounded,
                      color: climateGreen,
                      size: 27,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Smart Agriculture',
                          style: TextStyle(
                            color: climateNavy,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Forecast-based crop guidance',
                          style: TextStyle(color: climateMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_forward_rounded, color: climateGreen),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Check planting conditions, upcoming rain, irrigation needs, '
                'and weather-related crop risks for your selected district.',
                style: TextStyle(color: climateMuted, height: 1.4),
              ),
              const SizedBox(height: 15),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: const [
                  _AgricultureTag(icon: Icons.spa_outlined, label: 'Crop suitability'),
                  _AgricultureTag(icon: Icons.water_drop_outlined, label: 'Rain outlook'),
                  _AgricultureTag(icon: Icons.shield_outlined, label: 'Risk alerts'),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                decoration: BoxDecoration(
                  color: climateGreen,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.eco_outlined, color: Colors.white, size: 19),
                    SizedBox(width: 8),
                    Text(
                      'Explore agricultural forecast',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(
                color: climateMuted,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(
                color: climateNavy,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFD9E3EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: climateGreen,
            size: 25,
          ),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: climateMuted,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: climateNavy,
            ),
          ),
        ],
      ),
    );
  }
}


class _AgricultureTag extends StatelessWidget {
  final IconData icon;
  final String label;

  const _AgricultureTag({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF5EF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: climateGreen),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: climateNavy, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
