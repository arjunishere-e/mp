
import 'package:flutter/material.dart';

class DataSourcesScreen extends StatelessWidget {
  const DataSourcesScreen({super.key});

  static const sources = [
    ('INSAT', 'Satellite meteorological observations'),
    ('Oceansat', 'Ocean and coastal observations'),
    ('IMD', 'Ground-based weather observations'),
    ('ERA5', 'Historical climate reanalysis data'),
    ('Hydrological Data', 'River and water-resource information'),
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'DATA ACQUISITION',
          style: TextStyle(
            fontSize: 12,
            letterSpacing: 1.5,
            fontWeight: FontWeight.bold,
            color: Color(0xFF087E75),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Climate data sources',
          style: TextStyle(
            fontSize: 26,
            fontWeight: FontWeight.bold,
            color: Color(0xFF102A43),
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Sources planned for the Kerala Climate Twin prototype.',
          style: TextStyle(color: Color(0xFF627D98)),
        ),
        const SizedBox(height: 20),
        ...sources.map(
          (source) => Card(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFFD9E3EA)),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFDDF4ED),
                child: Icon(
                  Icons.satellite_alt,
                  color: Color(0xFF087E75),
                ),
              ),
              title: Text(
                source.$1,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(source.$2),
              ),
              trailing: const Chip(label: Text('Planned')),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Demo interface only — no live data is being collected.',
          style: TextStyle(
            fontSize: 12,
            color: Color(0xFF627D98),
          ),
        ),
      ],
    );
  }
}
