
import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const String historyApiUrl = 'http://10.0.2.2:8000';

const Color climateGreen = Color(0xFF00805F);
const Color climateNavy = Color(0xFF101B2D);

const List<String> climateDistricts = [
  'Thiruvananthapuram',
  'Kollam',
  'Pathanamthitta',
  'Alappuzha',
  'Kottayam',
  'Idukki',
  'Kochi',
  'Thrissur',
  'Palakkad',
  'Malappuram',
  'Kozhikode',
  'Wayanad',
  'Kannur',
  'Kasaragod',
];

class HistoricalAnalysisScreen extends StatefulWidget {
  const HistoricalAnalysisScreen({super.key});

  @override
  State<HistoricalAnalysisScreen> createState() =>
      _HistoricalAnalysisScreenState();
}

class _HistoricalAnalysisScreenState
    extends State<HistoricalAnalysisScreen> {
  String selectedDistrict = 'Kochi';

  DateTime startDate = DateTime(2025, 1, 1);
  DateTime endDate = DateTime(2025, 1, 31);

  Map<String, dynamic>? result;
  bool isLoading = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchHistory();
  }

  String dateString(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<void> fetchHistory() async {
    if (startDate.isAfter(endDate)) {
      setState(() {
        errorMessage = 'Start date must be before the end date.';
        result = null;
      });
      return;
    }

    if (endDate.difference(startDate).inDays > 366) {
      setState(() {
        errorMessage = 'Please select a period of at most 367 days.';
        result = null;
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
      result = null;
    });

    try {
      final uri = Uri.parse(
        '$historyApiUrl/api/climate/history/'
        '${Uri.encodeComponent(selectedDistrict)}',
      ).replace(
        queryParameters: {
          'start_date': dateString(startDate),
          'end_date': dateString(endDate),
        },
      );

      final response = await http
          .get(uri)
          .timeout(const Duration(seconds: 40));

      if (response.statusCode != 200) {
        String message = 'Unable to retrieve historical climate data.';
        try {
          final body = jsonDecode(response.body);
          if (body is Map && body['detail'] != null) {
            message = body['detail'].toString();
          }
        } catch (_) {}
        throw Exception(message);
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Invalid response from the climate API.');
      }

      if (!mounted) return;
      setState(() => result = decoded);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> chooseDate({required bool isStart}) async {
    final chosen = await showDatePicker(
      context: context,
      initialDate: isStart ? startDate : endDate,
      firstDate: DateTime(1940, 1, 1),
      lastDate: DateTime.now().subtract(const Duration(days: 6)),
      helpText: isStart ? 'Select start date' : 'Select end date',
    );

    if (chosen == null || !mounted) return;

    setState(() {
      if (isStart) {
        startDate = chosen;
      } else {
        endDate = chosen;
      }
    });
  }

  List<Map<String, dynamic>> get dailyRecords {
    final raw = result?['daily'];
    if (raw is! List) return [];

    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  }

  double? numberValue(dynamic value) {
    if (value is num) return value.toDouble();
    return null;
  }

  String formatNumber(dynamic value, String unit) {
    final number = numberValue(value);
    return number == null ? '--' : '${number.toStringAsFixed(1)}$unit';
  }

  Widget summaryCard(
    String title,
    String value,
    IconData icon,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE4ECE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: climateGreen, size: 23),
          const SizedBox(height: 12),
          Text(
            value,
            style: const TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.bold,
              color: climateNavy,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget chartCard({
    required String title,
    required String subtitle,
    required Widget chart,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE4ECE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: climateNavy,
              fontWeight: FontWeight.bold,
              fontSize: 17,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.black54,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(height: 220, child: chart),
        ],
      ),
    );
  }

  Widget buildTemperatureChart() {
    final records = dailyRecords;
    final points = <FlSpot>[];

    for (int i = 0; i < records.length; i++) {
      final value = numberValue(records[i]['temperature_mean_c']);
      if (value != null) {
        points.add(FlSpot(i.toDouble(), value));
      }
    }

    if (points.isEmpty) {
      return const Center(child: Text('No temperature data available.'));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (records.length - 1).toDouble().clamp(1, 366),
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Day'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: records.length > 60
                  ? 30
                  : records.length > 20
                      ? 7
                      : 5,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= records.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            axisNameWidget: Text('°C'),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: climateGreen,
            barWidth: 3,
            dotData: FlDotData(show: records.length <= 31),
            belowBarData: BarAreaData(
              show: true,
              color: climateGreen.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }

  Widget buildRainfallChart() {
    final records = dailyRecords;
    final bars = <BarChartGroupData>[];

    for (int i = 0; i < records.length; i++) {
      final value = numberValue(records[i]['precipitation_mm']);
      if (value != null) {
        bars.add(
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: value,
                color: const Color(0xFF42A5F5),
                width: records.length > 60 ? 3 : 8,
                borderRadius: BorderRadius.circular(3),
              ),
            ],
          ),
        );
      }
    }

    if (bars.isEmpty) {
      return const Center(child: Text('No rainfall data available.'));
    }

    return BarChart(
      BarChartData(
        barGroups: bars,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            axisNameWidget: const Text('Day'),
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: records.length > 60
                  ? 30
                  : records.length > 20
                      ? 7
                      : 5,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index < 0 || index >= records.length) {
                  return const SizedBox.shrink();
                }
                return SideTitleWidget(
                  meta: meta,
                  child: Text(
                    '${index + 1}',
                    style: const TextStyle(fontSize: 10),
                  ),
                );
              },
            ),
          ),
          leftTitles: const AxisTitles(
            axisNameWidget: Text('mm'),
            sideTitles: SideTitles(showTitles: true, reservedSize: 40),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = result?['summary'] as Map<String, dynamic>?;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F7),
      appBar: AppBar(
        title: const Text(
          'Historical Analysis',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: climateNavy,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Explore past climate patterns',
            style: TextStyle(
              fontSize: 21,
              fontWeight: FontWeight.bold,
              color: climateNavy,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Explore historical temperature and rainfall for Kerala locations.',
            style: TextStyle(color: Colors.black54),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFE4ECE9)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Analysis settings',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: climateNavy,
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedDistrict,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'District / location',
                    border: OutlineInputBorder(),
                  ),
                  items: climateDistricts
                      .map(
                        (district) => DropdownMenuItem(
                          value: district,
                          child: Text(district),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => selectedDistrict = value);
                    }
                  },
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => chooseDate(isStart: true),
                        child: Text('From\n${dateString(startDate)}'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => chooseDate(isStart: false),
                        child: Text('To\n${dateString(endDate)}'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: isLoading ? null : fetchHistory,
                    icon: const Icon(Icons.analytics_outlined),
                    label: const Text('Analyse climate'),
                    style: FilledButton.styleFrom(
                      backgroundColor: climateGreen,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          if (isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  children: [
                    CircularProgressIndicator(color: climateGreen),
                    SizedBox(height: 12),
                    Text('Loading historical climate data...'),
                  ],
                ),
              ),
            ),
          if (errorMessage != null && !isLoading)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0ED),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (result != null && !isLoading) ...[
            Text(
              '$selectedDistrict · ${dateString(startDate)} to ${dateString(endDate)}',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: climateNavy,
              ),
            ),
            const SizedBox(height: 12),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 1.45,
              children: [
                summaryCard(
                  'Average temperature',
                  formatNumber(
                    summary?['average_temperature_c'],
                    ' °C',
                  ),
                  Icons.thermostat,
                ),
                summaryCard(
                  'Total precipitation',
                  formatNumber(
                    summary?['total_precipitation_mm'],
                    ' mm',
                  ),
                  Icons.water_drop_outlined,
                ),
                summaryCard(
                  'Days returned',
                  '${summary?['days_returned'] ?? 0}',
                  Icons.calendar_month_outlined,
                ),
                summaryCard(
                  'Data model',
                  '${result?['model'] ?? 'ERA5'}',
                  Icons.public,
                ),
              ],
            ),
            const SizedBox(height: 18),
            chartCard(
              title: 'Daily temperature',
              subtitle: 'Mean daily temperature in °C',
              chart: buildTemperatureChart(),
            ),
            chartCard(
              title: 'Daily precipitation',
              subtitle: 'Daily precipitation total in mm',
              chart: buildRainfallChart(),
            ),
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: Text(
                'Source: Open-Meteo Historical Weather API. '
                'ERA5 values are reanalysis estimates, not direct '
                'measurements from local weather stations.',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.black54,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
