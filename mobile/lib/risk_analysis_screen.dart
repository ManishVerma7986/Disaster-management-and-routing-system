import 'package:flutter/material.dart';

/// Risk Analysis Screen - Shows detailed flood/landslide risk information
class RiskAnalysisScreen extends StatefulWidget {
  final Map<String, dynamic>? route;
  final Function(String)? onSelectRoute;

  const RiskAnalysisScreen({
    super.key,
    required this.route,
    this.onSelectRoute,
  });

  @override
  State<RiskAnalysisScreen> createState() => _RiskAnalysisScreenState();
}

class _RiskAnalysisScreenState extends State<RiskAnalysisScreen> {
  @override
  Widget build(BuildContext context) {
    final route = widget.route;

    if (route == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Risk Analysis'),
          centerTitle: true,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.warning_outlined, size: 64, color: Colors.orange),
              const SizedBox(height: 16),
              const Text(
                'No Route Selected',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              const Text(
                'Request a route from Home tab first to analyze risks',
                style: TextStyle(fontSize: 14, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Go to Home'),
              ),
            ],
          ),
        ),
      );
    }

    final recommended = route['recommended'];
    if (recommended == null || recommended is! Map) {
      return Scaffold(
        appBar: AppBar(title: const Text('Risk Analysis')),
        body: const Center(
          child: Text('Invalid route data'),
        ),
      );
    }

    final segments = (recommended['segments'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        [];
    final risk = recommended['risk'] as Map?;
    final warnings = (recommended['warnings'] as List?)?.whereType<String>().toList() ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Risk Analysis'),
        centerTitle: true,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Overall Risk Card
            Card(
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Overall Risk',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _RiskTile(
                            label: 'Flood',
                            level: risk?['flood'] ?? 'UNKNOWN',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RiskTile(
                            label: 'Landslide',
                            level: risk?['landslide'] ?? 'UNKNOWN',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RiskTile(
                            label: 'Traffic',
                            level: risk?['traffic'] ?? 'UNKNOWN',
                          ),
                        ),
                      ],
                    ),
                    if (risk?['confidence'] != null) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Confidence'),
                          Text(
                            '${risk!['confidence']}%',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Warnings Section
            if (warnings.isNotEmpty) ...[
              const Text(
                'Alerts',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              ...warnings.map(
                (warning) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.orange[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          warning,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.orange[900],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // Route Segments Section
            const Text(
              'Route Segments',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            if (segments.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No segment data available'),
              )
            else
              ...segments.asMap().entries.map((entry) {
                final index = entry.key;
                final segment = entry.value;
                final floodLevel = segment['flood_risk'] ?? 'UNKNOWN';
                final landslideLevel = segment['landslide_risk'] ?? 'UNKNOWN';

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              segment['road_name'] ?? 'Road ${index + 1}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.grey[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${segment['distance_km']} km',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: _SmallRiskTag(
                              label: 'Flood',
                              level: floodLevel,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _SmallRiskTag(
                              label: 'Landslide',
                              level: landslideLevel,
                            ),
                          ),
                        ],
                      ),
                      if (segment['warning'] != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          segment['warning'],
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}

/// Risk indicator tile
class _RiskTile extends StatelessWidget {
  final String label;
  final String level;

  const _RiskTile({
    required this.label,
    required this.level,
  });

  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.orange;
      case 'MEDIUM':
        return Colors.yellow[700]!;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLevelColor(level);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            level,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small risk tag for segments
class _SmallRiskTag extends StatelessWidget {
  final String label;
  final String level;

  const _SmallRiskTag({
    required this.label,
    required this.level,
  });

  Color _getLevelColor(String level) {
    switch (level.toUpperCase()) {
      case 'CRITICAL':
        return Colors.red;
      case 'HIGH':
        return Colors.orange;
      case 'MEDIUM':
        return Colors.yellow[700]!;
      case 'LOW':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getLevelColor(level);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 4),
          Text(
            level,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
