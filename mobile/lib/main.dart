import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'api_service.dart';
import 'location_monitor.dart';
import 'notification_service.dart';
import 'voice_navigation_service.dart';
import 'destination_search_service.dart';
import 'map_destination_picker.dart';
import 'registration_screen.dart';
import 'saved_route_store.dart';
import 'map_tile_config.dart';

void main() => runApp(const SafeRouteApp());

abstract final class AppColors {
  static const ink = Color(0xff102a2e);
  static const inkMuted = Color(0xff5c7375);
  static const canvas = Color(0xfff3f7f6);
  static const surface = Color(0xffffffff);
  static const primary = Color(0xff087f78);
  static const primaryDark = Color(0xff07524f);
  static const mint = Color(0xffdff3ef);
  static const warning = Color(0xffb85c00);
  static const warningSurface = Color(0xfffff3dc);
  static const danger = Color(0xffc23832);
  static const safe = Color(0xff16734b);
}

final ValueNotifier<ThemeMode> appThemeMode = ValueNotifier<ThemeMode>(ThemeMode.light);

bool _routeNeedsEmergencyMode(Map<String, dynamic>? route, String? status) {
  final recommended = route?['recommended'];
  final risk = recommended is Map && recommended['risk'] is Map
      ? '${(recommended['risk'] as Map)['overall']}'.toUpperCase()
      : '';
  final value = (status ?? '').toUpperCase();
  return risk == 'CRITICAL' ||
      value.contains('OFF ROUTE') ||
      value.contains('CRITICAL') ||
      value.contains('DANGER');
}

Map<String, dynamic>? _recommendedRoute(Map<String, dynamic>? route) {
  final recommended = route?['recommended'];
  if (recommended is Map) {
    return Map<String, dynamic>.from(recommended);
  }
  if (route != null && route['risk'] is Map && route['geometry'] is List) {
    return route;
  }
  return null;
}

class SafeRouteApp extends StatefulWidget {
  const SafeRouteApp({super.key});

  @override
  State<SafeRouteApp> createState() => _SafeRouteAppState();
}

class _SafeRouteAppState extends State<SafeRouteApp> {
  @override
  void initState() {
    super.initState();
    _restoreTheme();
  }

  Future<void> _restoreTheme() async {
    final preferences = await SharedPreferences.getInstance();
    final savedTheme = preferences.getString('theme_mode');
    final themeMode = switch (savedTheme) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.light,
    };
    if (!mounted) return;
    appThemeMode.value = themeMode;
  }

  ThemeData _theme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
      surface: dark ? const Color(0xff152326) : AppColors.surface,
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor:
          dark ? const Color(0xff0e1a1c) : AppColors.canvas,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? const Color(0xff0e1a1c) : AppColors.canvas,
        foregroundColor: dark ? Colors.white : AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: dark ? Colors.white : AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: dark ? const Color(0xff172a2d) : AppColors.surface,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? const Color(0xff1c3033) : AppColors.surface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: dark ? const Color(0xff122124) : AppColors.surface,
        indicatorColor: dark ? const Color(0xff24534f) : AppColors.mint,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
        ),
        height: 72,
      ),
      dividerTheme: DividerThemeData(
        color: dark ? Colors.white12 : const Color(0xffdce8e6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<ThemeMode>(
        valueListenable: appThemeMode,
        builder: (context, themeMode, _) {
          return MaterialApp(
            title: 'SafeRoute',
            debugShowCheckedModeBanner: false,
            theme: _theme(Brightness.light),
            darkTheme: _theme(Brightness.dark),
            themeMode: themeMode,
            home: const LoginScreen(),
          );
        },
      );
}

class WeatherDetailScreen extends StatefulWidget {
  const WeatherDetailScreen({
    super.key,
    required this.weather,
    required this.api,
    required this.position,
  });
  final Map<String, dynamic>? weather;
  final ApiService api;
  final Position? position;

  @override
  State<WeatherDetailScreen> createState() => _WeatherDetailScreenState();
}

class _WeatherDetailScreenState extends State<WeatherDetailScreen> {
  bool loading = false;
  Map<String, dynamic>? weatherData;

  @override
  void initState() {
    super.initState();
    weatherData = widget.weather;
  }

  Future<void> refreshWeather() async {
    if (loading) return;
    final currentPosition = widget.position;
    if (currentPosition == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location is unavailable.')));
      return;
    }
    setState(() => loading = true);
    try {
      final latitude = currentPosition.latitude;
      final longitude = currentPosition.longitude;
      final updatedWeather =
          await widget.api.weather(lat: latitude, lon: longitude);
      if (mounted) {
        setState(() {
          weatherData = updatedWeather;
          loading = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh weather: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Weather Details'),
        actions: [
          IconButton(
            onPressed: loading ? null : refreshWeather,
            tooltip: 'Refresh weather',
            icon: loading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: weatherData == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading weather data...'),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: const Color(0xffe7f2fb),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.cloud_outlined,
                              size: 48,
                              color: Color(0xff2d6f9f),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${weatherData!['condition']}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineLarge
                                        ?.copyWith(
                                          fontWeight: FontWeight.w800,
                                        ),
                                  ),
                                  if (weatherData!['location_name'] != null &&
                                      weatherData!['location_name']
                                          .toString()
                                          .isNotEmpty)
                                    Text(
                                      'Location: ${weatherData!['location_name']}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xff2d6f9f),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Rainfall ${weatherData!['rainfall_mm']} mm • ${weatherData!['source']}',
                          style: const TextStyle(fontSize: 16),
                        ),
                        if (weatherData!['observed_at'] != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Last updated: ${DateTime.parse(weatherData!['observed_at']).toLocal().toString().split('.')[0]}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Weather Metrics',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 16),
                        if (weatherData!['temp_celsius'] != null)
                          _WeatherMetric(
                            icon: Icons.thermostat_outlined,
                            label: 'Temperature',
                            value:
                                '${weatherData!['temp_celsius']?.toStringAsFixed(1)}°C',
                          ),
                        if (weatherData!['feels_like_celsius'] != null)
                          _WeatherMetric(
                            icon: Icons.thermostat,
                            label: 'Feels Like',
                            value:
                                '${weatherData!['feels_like_celsius']?.toStringAsFixed(1)}°C',
                          ),
                        if (weatherData!['humidity_percent'] != null)
                          _WeatherMetric(
                            icon: Icons.water_drop_outlined,
                            label: 'Humidity',
                            value: '${weatherData!['humidity_percent']}%',
                          ),
                        if (weatherData!['wind_speed_ms'] != null)
                          _WeatherMetric(
                            icon: Icons.air_outlined,
                            label: 'Wind Speed',
                            value:
                                '${weatherData!['wind_speed_ms']?.toStringAsFixed(1)} m/s',
                          ),
                        if (weatherData!['rainfall_mm'] != null)
                          _WeatherMetric(
                            icon: Icons.water_drop,
                            label: 'Rainfall',
                            value: '${weatherData!['rainfall_mm']} mm',
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.verified_outlined,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Live weather data from ${weatherData!['source']}',
                            style: TextStyle(
                              color: Colors.green.shade700,
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
}

class _WeatherMetric extends StatelessWidget {
  const _WeatherMetric({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xff2d6f9f)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final api = ApiService();
  bool loading = false;
  String? error;

  @override
  void initState() {
    super.initState();
    restoreSession();
  }

  Future<void> restoreSession() async {
    final user = await api.restoreSession();
    if (!mounted || user == null) return;
    Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => AppShell(api: api, user: user)));
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> login() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final response = await api.login(email.text.trim(), password.text);
      api.token = response['access_token'] as String;
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString('access_token', api.token!);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => AppShell(
              api: api, user: response['user'] as Map<String, dynamic>)));
    } catch (exception) {
      if (mounted) setState(() => error = exception.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
            gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xff081d20), Color(0xff123d42)])),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.shield_rounded,
                            size: 82, color: Color(0xffdff7f3)),
                        const SizedBox(height: 20),
                        const Text('DISASTER AWARE',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2)),
                        const Text('ROUTING',
                            style: TextStyle(
                                color: Color(0xff9ae3d7),
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2.2)),
                        const SizedBox(height: 12),
                        const Text('Stay Safe. Stay Informed.',
                            style: TextStyle(
                                color: Color(0xffd8f4ef), fontSize: 18)),
                        const SizedBox(height: 28),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextField(
                                    controller: email,
                                    keyboardType: TextInputType.emailAddress,
                                    decoration: const InputDecoration(
                                        labelText: 'Email',
                                        prefixIcon:
                                            Icon(Icons.email_outlined))),
                                const SizedBox(height: 12),
                                TextField(
                                    controller: password,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                        labelText: 'Password',
                                        prefixIcon: Icon(Icons.lock_outline))),
                                if (error != null)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: Text(error!,
                                          style: const TextStyle(
                                              color: Colors.red))),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                    onPressed: loading ? null : login,
                                    icon: const Icon(Icons.login_rounded),
                                    label: Text(
                                        loading ? 'Signing in...' : 'Sign in')),
                                TextButton(
                                    onPressed: loading
                                        ? null
                                        : () => Navigator.of(context).push(
                                            MaterialPageRoute(
                                                builder: (_) =>
                                                    RegistrationScreen(
                                                        api: api))),
                                    child: const Text('Create user account')),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.api, required this.user});
  final ApiService api;
  final Map<String, dynamic> user;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int tab = 0;
  Map<String, dynamic>? route;
  Position? position;
  String? status;
  bool online = true;
  List<dynamic> incidents = [];
  bool journeyActive = false;
  double? journeyProgress;
  double? remainingMeters;
  String routeSource = 'START';
  String routeDestination = 'DEST';
  String routeMode = 'EMERGENCY';
  final locationMonitor = LocationMonitor();
  final voice = VoiceNavigationService();
  final notifications = NotificationService();
  StreamSubscription<LocationEvent>? locationEvents;
  StreamSubscription<List<ConnectivityResult>>? connectivityEvents;
  StreamSubscription<Map<String, dynamic>>? incidentEvents;
  Timer? incidentReconnect;
  bool routeMapFullscreen = false;

  @override
  void initState() {
    super.initState();
    loadIncidents();
    connectIncidentStream();
    monitorConnectivity();
    loadCachedRoute();
    locationEvents = locationMonitor.events.listen((event) {
      if (!mounted) return;
      setState(() {
        position = event.position;
        if (journeyActive) {
          journeyProgress = event.progress;
          remainingMeters = event.remainingMeters;
          status = event.type == LocationEventType.offRoute
              ? 'OFF ROUTE - ${event.distanceMeters?.round() ?? 0} m away'
              : 'JOURNEY ACTIVE - LIVE GPS';
        }
      });
      if (journeyActive && (event.progress ?? 0) >= 0.99) {
        endJourney();
      }
    });
    locate();
  }

  /*
                TextField(controller: source, onChanged: searchSources, decoration: InputDecoration(labelText: 'Starting point', hintText: 'Search a place or use your location', prefixIcon: const Icon(Icons.my_location), suffixIcon: _FieldActions(loading: searchingSource, listening: listening, onVoice: () => listenForField(source, isSource: true), onMap: chooseSourceFromMap))),
                if (sourceSuggestions.isNotEmpty) _SuggestionList(suggestions: sourceSuggestions, onSelected: (item) => setState(() { source.text = '@${item.latitude},${item.longitude}'; sourceSuggestions = []; })),
                if (sourceSearchError != null) Align(alignment: Alignment.centerLeft, child: Text(sourceSearchError!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 12),
                TextField(controller: destination, focusNode: destinationFocus, onChanged: searchDestinations, decoration: InputDecoration(labelText: 'Where are you going?', prefixIcon: const Icon(Icons.place_outlined), suffixIcon: _FieldActions(loading: searching, listening: listening, onVoice: () => listenForField(destination, isSource: false), onMap: chooseFromMap))),
                if (suggestions.isNotEmpty) _SuggestionList(suggestions: suggestions, onSelected: (item) => setState(() { destination.text = '@${item.latitude},${item.longitude}'; suggestions = []; })),
                if (searchError != null) Align(alignment: Alignment.centerLeft, child: Text(searchError!, style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(initialValue: mode, decoration: const InputDecoration(labelText: 'Routing mode'), items: ['EMERGENCY', 'DRIVING', 'WALKING', 'CYCLING'].map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => mode = value!)),
                const SizedBox(height: 14),
                SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: loading ? null : findRoute, icon: const Icon(Icons.route), label: Text(loading ? 'Checking roads...' : 'Find route'))),
                      height: 88,
                      decoration: BoxDecoration(
                        color: const Color(0xffdff7f3),
                        borderRadius: BorderRadius.circular(28),
                      ),
                      child: const Icon(
                        Icons.shield_rounded,
                        size: 50,
                        color: Color(0xff0d756d),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'DISASTER AWARE',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 1.2,
                              ),
                      textAlign: TextAlign.center,
                    ),
                    Text(
                      'ROUTING',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: const Color(0xff9ae3d7),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2.2,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Stay Safe. Stay Informed.',
                      style: TextStyle(
                        color: Color(0xffd8f4ef),
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(controller: email, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined))),
                            const SizedBox(height: 12),
                            TextField(controller: password, obscureText: true, decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline))),
                            if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.red))),
                            const SizedBox(height: 18),
                            FilledButton.icon(onPressed: loading ? null : login, icon: const Icon(Icons.login_rounded), label: Text(loading ? 'Signing in...' : 'Sign in'), style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
                            const SizedBox(height: 12),
                            TextButton(onPressed: loading ? null : () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => RegistrationScreen(api: api))), child: const Text('Create user account')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

  */
  Future<void> loadIncidents() async {
    try {
      final values = await widget.api.incidents();
      if (mounted) setState(() => incidents = values);
    } catch (_) {}
  }

  void connectIncidentStream() {
    incidentReconnect?.cancel();
    incidentEvents?.cancel();
    incidentEvents = widget.api.incidentUpdates().listen((event) {
      final incident = event['incident'];
      if (!mounted || incident is! Map) return;
      final updated = Map<String, dynamic>.from(incident);
      setState(() {
        final index =
            incidents.indexWhere((item) => item['id'] == updated['id']);
        if (index == -1) {
          incidents = [updated, ...incidents];
        } else {
          incidents = [...incidents]..[index] = updated;
        }
      });
    },
        onDone: scheduleIncidentReconnect,
        onError: (_) => scheduleIncidentReconnect());
  }

  void scheduleIncidentReconnect() {
    if (!mounted || incidentReconnect?.isActive == true) return;
    incidentReconnect =
        Timer(const Duration(seconds: 5), connectIncidentStream);
  }

  Future<void> monitorConnectivity() async {
    final connectivity = Connectivity();
    final initial = await connectivity.checkConnectivity();
    if (mounted)
      setState(() => online = !initial.contains(ConnectivityResult.none));
    connectivityEvents = connectivity.onConnectivityChanged.listen((results) {
      if (mounted)
        setState(() => online = !results.contains(ConnectivityResult.none));
    });
  }

  Future<void> registerNotifications() async {
    await notifications.initialize();
    final token = await notifications.token();
    if (token != null)
      await widget.api.registerPushToken(token, widget.api.platformLabel);
  }

  @override
  void dispose() {
    locationEvents?.cancel();
    connectivityEvents?.cancel();
    incidentEvents?.cancel();
    incidentReconnect?.cancel();
    locationMonitor.dispose();
    super.dispose();
  }

  Future<void> loadCachedRoute() async {
    final cached = await widget.api.cachedRoute();
    if (mounted && cached != null)
      setState(() {
        route = cached;
        status = 'OFFLINE CACHE AVAILABLE';
      });
  }

  Future<void> locate() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Location services are disabled');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw Exception('Location permission was not granted');
      final value = await Geolocator.getCurrentPosition();
      if (mounted) setState(() => position = value);
    } catch (exception) {
      if (mounted) setState(() => status = exception.toString());
    }
  }

  Future<void> requestRoute(
      String source, String destination, String mode) async {
    routeSource = source;
    routeDestination = destination;
    routeMode = mode;
    setState(() => status = 'Checking current road conditions...');
    try {
      if (await widget.api.cachedSync() == null) await widget.api.sync();
      final value = await widget.api.route(source, destination, mode);
      if (mounted) {
        setState(() {
          route = value;
          status = value['data_status'] == 'OFFLINE CACHE'
              ? 'OFFLINE ROUTING'
              : 'LIVE ROUTE DATA';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => status = 'Showing cached route: $exception');
    }
  }

  Future<void> openFacility(Map<String, dynamic> facility) async {
    // Try multiple possible coordinate field names
    final latitude =
        facility['lat'] ?? facility['latitude'] ?? facility['lat_degrees'];
    final longitude =
        facility['lon'] ?? facility['longitude'] ?? facility['lon_degrees'];

    print('🏥 Facility data: $facility');
    print('🏥 Extracted coordinates: lat=$latitude, lon=$longitude');

    // Handle string coordinates
    double? latDouble;
    double? lonDouble;

    if (latitude is num) {
      latDouble = latitude.toDouble();
    } else if (latitude is String) {
      latDouble = double.tryParse(latitude);
    }

    if (longitude is num) {
      lonDouble = longitude.toDouble();
    } else if (longitude is String) {
      lonDouble = double.tryParse(longitude);
    }

    if (latDouble == null || lonDouble == null) {
      print('❌ Invalid facility coordinates: lat=$latDouble, lon=$lonDouble');
      print('❌ Available keys: ${facility.keys.toList()}');
      setState(() => status = 'Invalid facility coordinates. Cannot navigate.');
      return;
    }

    print('🏥 Opening facility: ${facility['name']} at $latDouble, $lonDouble');

    // Ensure we have current location
    if (position == null) {
      print('📍 Getting current location...');
      await locate();
    }

    final current = position;
    if (current == null || !mounted) {
      print('❌ Cannot get current location or widget not mounted');
      setState(
          () => status = 'Cannot get current location. Enable GPS services.');
      return;
    }

    // Set source and destination for the route
    routeSource = '@${current.latitude},${current.longitude}';
    routeDestination = '@$latDouble,$lonDouble';

    print('🚀 Requesting route from $routeSource to $routeDestination');
    print('🚀 Current location: ${current.latitude}, ${current.longitude}');
    print('🚀 Destination: $latDouble, $lonDouble');

    // Request the route in EMERGENCY mode for quick response
    setState(() => status = 'Calculating route to ${facility['name']}...');

    try {
      await requestRoute(routeSource, routeDestination, 'EMERGENCY');
    } catch (e) {
      print('❌ Route request failed: $e');
      setState(() => status = 'Route calculation failed: $e');
      return;
    }

    if (mounted) {
      // Switch to the map tab (tab 1)
      setState(() {
        tab = 1;
        if (route != null) {
          status =
              'Route to ${facility['name']} calculated. Starting navigation...';
        } else {
          status =
              'Failed to calculate route to ${facility['name']}. Check backend connectivity.';
        }
      });

      // Give the UI a moment to update before starting the journey
      await Future.delayed(const Duration(milliseconds: 500));

      // Automatically start the journey
      if (route != null) {
        print('🎯 Starting journey to facility');
        print('🎯 Route data: ${route!.keys}');
        await startJourney();
      } else {
        print('❌ Route calculation failed, cannot start journey');
        setState(() => status =
            'Failed to calculate route to facility. Check backend logs.');
      }
    }
  }

  Future<void> startJourney() async {
    if (route == null) return;
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw Exception('Location services are disabled.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw Exception('Location permission was not granted.');
      final recommended = _recommendedRoute(route);
      if (recommended == null) {
        throw const FormatException('Route data is unavailable or invalid.');
      }
      final geometry = (recommended['geometry'] as List?)
          ?.map((point) =>
              [(point[0] as num).toDouble(), (point[1] as num).toDouble()])
          .toList();
      locationMonitor.start(routeGeometry: geometry);
      setState(() {
        journeyActive = true;
        journeyProgress = 0;
        remainingMeters = null;
        status = 'JOURNEY ACTIVE - LIVE GPS';
      });
      await HapticFeedback.heavyImpact();
      await voice.routeStarted(recommended);
    } catch (error) {
      if (mounted) setState(() => status = error.toString());
    }
  }

  Future<void> endJourney() async {
    await locationMonitor.stop();
    if (mounted)
      setState(() {
        journeyActive = false;
        journeyProgress = null;
        remainingMeters = null;
        status = 'Journey ended';
      });
    await voice.stop();
  }

  @override
  Widget build(BuildContext context) {
    final authority =
        widget.user['role'] == 'AUTHORITY' || widget.user['role'] == 'ADMIN';
    final emergencyMode = _routeNeedsEmergencyMode(route, status);
    final pages = [
      HomeTab(
          onRoute: requestRoute,
          route: route,
          position: position,
          status: status,
          emergencyMode: emergencyMode,
          onChooseFromMap: chooseDestinationFromMap,
          onChooseSourceFromMap: chooseSourceFromMap,
          onEmergency: () => setState(() => tab = 5),
          onLiveCheck: () => setState(() => tab = 2),
          api: widget.api),
      RouteTab(
          route: route,
          incidents: incidents,
          position: position,
          journeyActive: journeyActive,
          journeyProgress: journeyProgress,
          remainingMeters: remainingMeters,
          onStartJourney: startJourney,
          onEndJourney: endJourney,
          fullscreen: routeMapFullscreen,
          onToggleFullscreen: () =>
              setState(() => routeMapFullscreen = !routeMapFullscreen)),
      SituationTab(
          api: widget.api,
          position: position,
          active: tab == 2,
          onOpenFacility: openFacility),
      ReportsTab(
          api: widget.api,
          position: position,
          active: tab == 3,
          onReportSubmitted: loadIncidents),
      OfflineTab(
          api: widget.api,
          route: route,
          source: routeSource,
          destination: routeDestination,
          mode: routeMode,
          onOpen: (value) => setState(() {
                route = value;
                tab = 1;
              })),
      EmergencyTab(
          api: widget.api,
          position: position,
          active: tab == 5,
          onOpenFacility: openFacility),
      if (authority) AuthorityTab(api: widget.api),
      ProfileTab(
          user: widget.user,
          themeMode: appThemeMode.value,
          onThemeModeChanged: (mode) async {
            appThemeMode.value = mode;
            final preferences = await SharedPreferences.getInstance();
            await preferences.setString('theme_mode', mode.name);
          },
          onLogout: () async {
            await widget.api.logout();
            if (mounted) {
              Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (_) => false);
            }
          })
    ];
    final destinations = [
      const NavigationDestination(
          icon: Icon(Icons.home_outlined), label: 'Home'),
      const NavigationDestination(icon: Icon(Icons.alt_route), label: 'Route'),
      const NavigationDestination(
          icon: Icon(Icons.warning_amber_outlined), label: 'Situation'),
      const NavigationDestination(
          icon: Icon(Icons.report_outlined), label: 'Reports'),
      const NavigationDestination(
          icon: Icon(Icons.offline_bolt_outlined), label: 'Offline'),
      const NavigationDestination(icon: Icon(Icons.sos), label: 'Emergency'),
      if (authority)
        const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined), label: 'Authority'),
      const NavigationDestination(
          icon: Icon(Icons.person_outline), label: 'Profile')
    ];
    return Scaffold(
        appBar: AppBar(
            title: Row(children: [
              const Text('SafeRoute'),
              if (!online) ...[
                const SizedBox(width: 10),
                const Icon(Icons.cloud_off, size: 17, color: Color(0xffb45a00)),
                const SizedBox(width: 4),
                const Text('Offline',
                    style: TextStyle(fontSize: 12, color: Color(0xffb45a00)))
              ]
            ]),
            actions: [
              IconButton(
                  onPressed: locate,
                  tooltip: 'Refresh location',
                  icon: const Icon(Icons.my_location))
            ]),
        body: Column(children: [
          if (!online)
            Container(
                width: double.infinity,
                color: const Color(0xfffff2d6),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: const Row(children: [
                  Icon(Icons.wifi_off, size: 18, color: Color(0xff713a00)),
                  SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          'You are offline. Cached routes and saved reports remain available.',
                          style: TextStyle(color: Color(0xff713a00))))
                ])),
          Expanded(child: pages[tab])
        ]),
        bottomNavigationBar: NavigationBar(
            selectedIndex: tab,
            onDestinationSelected: (value) => setState(() => tab = value),
            labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
            destinations: destinations));
  }

  Future<DestinationSuggestion?> chooseDestinationFromMap() async {
    return chooseMapPoint((selected) {
      routeDestination = '@${selected.latitude},${selected.longitude}';
      status = 'Map destination selected';
    });
  }

  Future<DestinationSuggestion?> chooseSourceFromMap() async {
    return chooseMapPoint((selected) {
      routeSource = '@${selected.latitude},${selected.longitude}';
      status = 'Map starting point selected';
    });
  }

  Future<DestinationSuggestion?> chooseMapPoint(
      void Function(DestinationSuggestion) applySelection) async {
    final selected = await Navigator.of(context).push<DestinationSuggestion>(
        MaterialPageRoute(builder: (_) => const MapDestinationPicker()));
    if (selected == null || !mounted) return selected;
    setState(() => applySelection(selected));
    return selected;
  }
}

class HomeTab extends StatefulWidget {
  const HomeTab(
      {super.key,
      required this.onRoute,
      required this.route,
      required this.position,
      required this.status,
      required this.emergencyMode,
      required this.onChooseFromMap,
      required this.onChooseSourceFromMap,
      required this.onEmergency,
      this.onLiveCheck,
      required this.api});
  final Future<void> Function(String, String, String) onRoute;
  final Map<String, dynamic>? route;
  final Position? position;
  final String? status;
  final bool emergencyMode;
  final Future<DestinationSuggestion?> Function() onChooseFromMap;
  final Future<DestinationSuggestion?> Function() onChooseSourceFromMap;
  final VoidCallback onEmergency;
  final VoidCallback? onLiveCheck;
  final ApiService api;
  @override
  State<HomeTab> createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final source = TextEditingController(text: 'START');
  final destination = TextEditingController(text: 'DEST');
  String mode = 'EMERGENCY';
  bool loading = false;
  bool searching = false;
  bool searchingSource = false;
  String? searchError;
  String? sourceSearchError;
  List<DestinationSuggestion> suggestions = [];
  List<DestinationSuggestion> sourceSuggestions = [];
  final searchService = DestinationSearchService(baseUrl: ApiService().baseUrl);
  final destinationFocus = FocusNode();
  final speech = SpeechToText();
  bool listening = false;

  // Weather and warnings state
  Map<String, dynamic>? weather;
  List<dynamic> warnings = [];
  bool weatherLoading = false;

  @override
  void didUpdateWidget(covariant HomeTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position &&
        source.text == 'START' &&
        widget.position != null) {
      source.text =
          '@${widget.position!.latitude},${widget.position!.longitude}';
    }
    // Load weather data when position changes
    if (widget.position != oldWidget.position) {
      loadWeatherAndWarnings();
    }
  }

  @override
  void initState() {
    super.initState();
    loadWeatherAndWarnings();
  }

  Future<void> loadWeatherAndWarnings() async {
    if (weatherLoading) return;
    final currentPosition = widget.position;
    if (currentPosition == null) {
      if (mounted) {
        setState(() {
          weather = null;
          warnings = [];
        });
      }
      return;
    }
    setState(() => weatherLoading = true);
    try {
      final latitude = currentPosition.latitude;
      final longitude = currentPosition.longitude;
      final values = await Future.wait([
        widget.api.weather(lat: latitude, lon: longitude),
        widget.api.nearbyWarnings(lat: latitude, lon: longitude),
      ]);
      if (mounted) {
        setState(() {
          weather = values[0] as Map<String, dynamic>;
          warnings = values[1] as List<dynamic>;
        });
      }
    } catch (_) {
      // Silently fail - weather is optional for home tab
    } finally {
      if (mounted) setState(() => weatherLoading = false);
    }
  }

  @override
  void dispose() {
    source.dispose();
    destination.dispose();
    destinationFocus.dispose();
    searchService.dispose();
    super.dispose();
  }

  Future<void> findRoute() async {
    if (destination.text.trim().isEmpty) {
      setState(() => searchError = 'Enter or choose a destination first.');
      return;
    }
    setState(() {
      loading = true;
      searchError = null;
    });
    await widget.onRoute(source.text.trim(), destination.text.trim(), mode);
    if (mounted) setState(() => loading = false);
  }

  Future<void> searchDestinations(String value) async {
    if (value.trim().length < 3) {
      setState(() {
        suggestions = [];
        searching = false;
        searchError = null;
      });
      return;
    }
    setState(() {
      searching = true;
      searchError = null;
    });
    try {
      final values = await searchService.debouncedSearch(value);
      if (mounted)
        setState(() {
          suggestions = values;
          searching = false;
        });
    } catch (error) {
      if (mounted)
        setState(() {
          suggestions = [];
          searching = false;
          searchError =
              'Destination search unavailable. You can still use START/DEST or cached routing.';
        });
    }
  }

  Future<void> searchSources(String value) async {
    if (value.trim().length < 3) {
      setState(() {
        sourceSuggestions = [];
        searchingSource = false;
        sourceSearchError = null;
      });
      return;
    }
    setState(() {
      searchingSource = true;
      sourceSearchError = null;
    });
    try {
      final values = await searchService.debouncedSearch(value);
      if (mounted)
        setState(() {
          sourceSuggestions = values;
          searchingSource = false;
        });
    } catch (_) {
      if (mounted)
        setState(() {
          sourceSuggestions = [];
          searchingSource = false;
          sourceSearchError = 'Starting-point search is unavailable.';
        });
    }
  }

  Future<void> chooseFromMap() async {
    final selected = await widget.onChooseFromMap();
    if (selected != null && mounted) {
      destination.text = '@${selected.latitude},${selected.longitude}';
      setState(() {
        suggestions = [];
        searchError = null;
      });
    }
  }

  Future<void> chooseSourceFromMap() async {
    final selected = await widget.onChooseSourceFromMap();
    if (selected != null && mounted) {
      source.text = '@${selected.latitude},${selected.longitude}';
      setState(() {
        sourceSuggestions = [];
        sourceSearchError = null;
      });
    }
  }

  Future<void> listenForField(TextEditingController controller,
      {required bool isSource}) async {
    if (listening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    final available = await speech.initialize();
    if (!available) {
      if (mounted)
        setState(
            () => searchError = 'Voice input is unavailable on this device.');
      return;
    }
    if (mounted) setState(() => listening = true);
    await speech.listen(onResult: (result) {
      if (!mounted) return;
      controller.text = result.recognizedWords;
      if (result.finalResult) {
        setState(() => listening = false);
        if (isSource) {
          searchSources(controller.text);
        } else {
          searchDestinations(controller.text);
        }
      }
    });
  }

  void _showRiskDialog(BuildContext context) {
    final recommended = _recommendedRoute(widget.route);
    if (recommended == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Route Risk'),
          content: const Text(
              'No route selected. Please find a route first to see risk assessment.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    final riskMap = recommended['risk'] is Map
        ? recommended['risk'] as Map<String, dynamic>
        : {};
    final risk = '${riskMap['overall'] ?? 'UNKNOWN'}'.toUpperCase();
    final confidence = riskMap['confidence'] is num
        ? (riskMap['confidence'] as num).toInt()
        : 0;

    final riskColor = risk.contains('HIGH') || risk.contains('CRITICAL')
        ? const Color(0xffb3261e)
        : risk.contains('MEDIUM') || risk.contains('MODERATE')
            ? const Color(0xffb45a00)
            : const Color(0xff16734b);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Current Route Risk'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.shield_outlined, color: riskColor),
                const SizedBox(width: 8),
                Text(
                  risk,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: riskColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text('Confidence: $confidence%'),
            const SizedBox(height: 8),
            if (riskMap['flood'] != null)
              Text('Flood Risk: ${riskMap['flood']}'),
            if (riskMap['landslide'] != null)
              Text('Landslide Risk: ${riskMap['landslide']}'),
            if (riskMap['weather'] != null)
              Text('Weather Risk: ${riskMap['weather']}'),
            if (riskMap['traffic'] != null)
              Text('Traffic Risk: ${riskMap['traffic']}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final recommended = _recommendedRoute(widget.route);
    final locationLabel = widget.position == null
        ? 'Location permission or GPS unavailable'
        : 'GPS accuracy ${widget.position!.accuracy.toStringAsFixed(0)} m';
    final statusLabel = widget.status ?? 'Monitoring local road conditions';
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        if (widget.emergencyMode) ...[
          const _EmergencyModeBanner(),
          const SizedBox(height: 14),
        ],
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: widget.emergencyMode
                  ? const [Color(0xff743331), Color(0xffb85c00)]
                  : const [AppColors.primaryDark, AppColors.primary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withOpacity(.16),
                blurRadius: 22,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Emergency control center',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: const BoxDecoration(
                            color: Color(0xff8de0ae),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.position == null
                                ? 'Waiting for your location'
                                : 'Location monitoring is active',
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      widget.emergencyMode
                          ? 'Emergency response is prioritized'
                          : locationLabel,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              const CircleAvatar(
                radius: 27,
                backgroundColor: Colors.white24,
                child:
                    Icon(Icons.shield_rounded, color: Colors.white, size: 30),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Dedicated Weather & Warnings Panel (compact version for home)
        Card(
          color: AppColors.warningSurface,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Color(0xffb45a00), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Active warnings',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: const Color(0xff713a00))),
                      const SizedBox(height: 4),
                      if (warnings.isNotEmpty)
                        Text('${warnings.length} active warning(s) nearby',
                            style: const TextStyle(color: Color(0xff713a00))),
                      if (weather != null)
                        Text(
                            '${weather!['condition']} • ${weather!['temp_celsius']?.toStringAsFixed(0)}°C',
                            style: const TextStyle(color: Color(0xff713a00))),
                      if (warnings.isEmpty && weather == null)
                        Text(statusLabel,
                            style: const TextStyle(color: Color(0xff713a00))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text('Quick actions',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: const Color(0xff10353a))),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
                child: _QuickAction(
                    icon: Icons.route,
                    label: 'Plan route',
                    onTap: () =>
                        FocusScope.of(context).requestFocus(destinationFocus))),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickAction(
                    icon: Icons.map_outlined,
                    label: 'Pick on map',
                    onTap: chooseFromMap)),
            const SizedBox(width: 10),
            Expanded(
                child: _QuickAction(
                    icon: Icons.sos,
                    label: 'Emergency',
                    onTap: widget.onEmergency)),
          ],
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
                child: _StatusMetric(
                    icon: Icons.cloud_outlined,
                    label: 'Weather',
                    value: 'Monitoring',
                    color: const Color(0xff2d6f9f),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => WeatherDetailScreen(
                            weather: weather,
                            api: widget.api,
                            position: widget.position,
                          ),
                        ),
                      );
                    })),
            const SizedBox(width: 10),
            Expanded(
                child: _StatusMetric(
                    icon: Icons.traffic_outlined,
                    label: 'Roads',
                    value: 'Live check',
                    color: const Color(0xffb45a00),
                    onTap: widget.onLiveCheck)),
            const SizedBox(width: 10),
            Expanded(
                child: _StatusMetric(
                    icon: Icons.shield_outlined,
                    label: 'Risk',
                    value: 'Assessing',
                    color: const Color(0xff0f6b66),
                    onTap: () {
                      _showRiskDialog(context);
                    })),
          ],
        ),
        const SizedBox(height: 22),
        Text('Find a safer route',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800, color: const Color(0xff10353a))),
        const SizedBox(height: 10),
        Card(
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                /*
                TextField(
                    controller: source,
                  onChanged: searchSources,
                  decoration: InputDecoration(
                    labelText: 'Starting point',
                    hintText: 'Search a place or use your location',
                    prefixIcon: const Icon(Icons.my_location),
                    suffixIcon: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (searchingSource)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))),
                      IconButton(
                        tooltip: 'Use voice for starting point',
                        onPressed: () => listenForField(source, isSource: true),
                        icon: Icon(listening ? Icons.mic : Icons.mic_none,
                          color: listening ? const Color(0xffb3261e) : null)),
                      IconButton(
                        tooltip: 'Choose starting point on map',
                        onPressed: chooseSourceFromMap,
                        icon: const Icon(Icons.map_outlined))
                    ])),
                if (sourceSuggestions.isNotEmpty)
                  Card(
                    child: Column(
                      children: sourceSuggestions
                        .map((item) => ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(item.name),
                          subtitle: Text(item.displayName),
                          onTap: () {
                          source.text =
                            '@${item.latitude},${item.longitude}';
                          setState(() => sourceSuggestions = []);
                          }))
                        .toList())),
                if (sourceSearchError != null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(sourceSearchError!,
                        style: const TextStyle(color: Colors.red)))),
                const SizedBox(height: 12),
                TextField(
                  controller: destination,
                  focusNode: destinationFocus,
                  onChanged: searchDestinations,
                  decoration: InputDecoration(
                      labelText: 'Where are you going?',
                      prefixIcon: const Icon(Icons.place_outlined),
                      suffixIcon:
                          Row(mainAxisSize: MainAxisSize.min, children: [
                        if (searching)
                          const Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                      strokeWidth: 2))),
                        IconButton(
                            tooltip: listening
                                ? 'Stop voice input'
                                : 'Use voice input',
                            onPressed: () =>
                              listenForField(destination, isSource: false),
                            icon: Icon(listening ? Icons.mic : Icons.mic_none,
                                color:
                                    listening ? const Color(0xffb3261e) : null))
                      OutlinedButton.icon(
                          onPressed: chooseFromMap,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Choose destination on map')),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                          initialValue: mode,
                          decoration: const InputDecoration(labelText: 'Routing mode'),
                          items: [
                                  }))
                              .toList())),
                if (searchError != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(searchError!,
                          style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                          onPressed: chooseFromMap,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('Choose on map')),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                          initialValue: mode,
                          decoration: const InputDecoration(labelText: 'Mode'),
                          items: [
                            'EMERGENCY',
                            'DRIVING',
                            'WALKING',
                            'CYCLING'
                          ]
                              .map((value) => DropdownMenuItem(
                                  value: value, child: Text(value)))
                              .toList(),
                    onChanged: (value) => setState(() => mode = value!)),
                const SizedBox(height: 14),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: loading ? null : findRoute,
                        icon: const Icon(Icons.route),
                        label: Text(loading
                            ? 'Checking roads...'
                            : 'Find safest route'))),
              ],
            ),
          ),
        ),
                */
                TextField(
                    controller: source,
                    onChanged: searchSources,
                    decoration: InputDecoration(
                        labelText: 'Starting point',
                        hintText: 'Search a place or use your location',
                        prefixIcon: const Icon(Icons.my_location),
                        suffixIcon: _FieldActions(
                            loading: searchingSource,
                            listening: listening,
                            onVoice: () =>
                                listenForField(source, isSource: true),
                            onMap: chooseSourceFromMap))),
                if (sourceSuggestions.isNotEmpty)
                  _SuggestionList(
                      suggestions: sourceSuggestions,
                      onSelected: (item) => setState(() {
                            source.text = '@${item.latitude},${item.longitude}';
                            sourceSuggestions = [];
                          })),
                if (sourceSearchError != null)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(sourceSearchError!,
                          style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 12),
                TextField(
                    controller: destination,
                    focusNode: destinationFocus,
                    onChanged: searchDestinations,
                    decoration: InputDecoration(
                        labelText: 'Where are you going?',
                        prefixIcon: const Icon(Icons.place_outlined),
                        suffixIcon: _FieldActions(
                            loading: searching,
                            listening: listening,
                            onVoice: () =>
                                listenForField(destination, isSource: false),
                            onMap: chooseFromMap))),
                if (suggestions.isNotEmpty)
                  _SuggestionList(
                      suggestions: suggestions,
                      onSelected: (item) => setState(() {
                            destination.text =
                                '@${item.latitude},${item.longitude}';
                            suggestions = [];
                          })),
                if (searchError != null)
                  Align(
                      alignment: Alignment.centerLeft,
                      child: Text(searchError!,
                          style: const TextStyle(color: Colors.red))),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                    initialValue: mode,
                    decoration: const InputDecoration(
                      labelText: 'Routing mode',
                      prefixIcon: Icon(Icons.tune_rounded),
                    ),
                    items: ['EMERGENCY', 'DRIVING', 'WALKING', 'CYCLING']
                        .map((value) =>
                            DropdownMenuItem(value: value, child: Text(value)))
                        .toList(),
                    onChanged: (value) => setState(() => mode = value!)),
                const SizedBox(height: 14),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                        onPressed: loading ? null : findRoute,
                        icon: const Icon(Icons.alt_route_rounded),
                        label: Text(loading
                            ? 'Checking roads...'
                            : 'Find safest route'))),
              ],
            ),
          ),
        ),
        if (recommended != null) RouteSummary(route: recommended)
      ],
    );
  }
}

class _FieldActions extends StatelessWidget {
  const _FieldActions({
    required this.loading,
    required this.listening,
    required this.onVoice,
    required this.onMap,
  });
  final bool loading;
  final bool listening;
  final VoidCallback onVoice;
  final VoidCallback onMap;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        if (loading)
          const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))),
        IconButton(
            tooltip: listening ? 'Stop voice input' : 'Use voice input',
            onPressed: onVoice,
            icon: Icon(listening ? Icons.mic : Icons.mic_none,
                color: listening ? const Color(0xffb3261e) : null)),
        IconButton(
            tooltip: 'Choose on map',
            onPressed: onMap,
            icon: const Icon(Icons.map_outlined))
      ]);
}

class _SuggestionList extends StatelessWidget {
  const _SuggestionList({required this.suggestions, required this.onSelected});
  final List<DestinationSuggestion> suggestions;
  final ValueChanged<DestinationSuggestion> onSelected;

  @override
  Widget build(BuildContext context) => Card(
      child: Column(
          children: suggestions
              .map((item) => ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(item.name),
                  subtitle: Text(item.displayName),
                  onTap: () => onSelected(item)))
              .toList()));
}

class _QuickAction extends StatelessWidget {
  const _QuickAction(
      {required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          padding: const EdgeInsets.fromLTRB(8, 16, 8, 14),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.mint),
          ),
          child: Column(children: [
            CircleAvatar(
              radius: 21,
              backgroundColor: AppColors.mint,
              child: Icon(icon, color: AppColors.primaryDark),
            ),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))
          ]),
        ),
      );
}

/// Dedicated Weather & Warnings Panel
class WeatherWarningsPanel extends StatelessWidget {
  const WeatherWarningsPanel({
    super.key,
    required this.weather,
    required this.warnings,
    this.onRefresh,
    this.refreshing = false,
  });

  final Map<String, dynamic>? weather;
  final List<dynamic> warnings;
  final VoidCallback? onRefresh;
  final bool refreshing;

  void _showWarningDetails(BuildContext context, Map<String, dynamic> warning) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${warning['title'] ?? warning['type'] ?? 'Warning'}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _WarningDetailRow(
                label: 'Severity',
                value: '${warning['severity'] ?? 'UNKNOWN'}',
              ),
              if (warning['description'] != null)
                _WarningDetailRow(
                  label: 'Details',
                  value: '${warning['description']}',
                ),
              _WarningDetailRow(
                label: 'Radius',
                value: '${warning['radius_km'] ?? 5} km',
              ),
              if (warning['source'] != null)
                _WarningDetailRow(
                  label: 'Source',
                  value: '${warning['source']}',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Close'),
          ),
          if (_warningCoordinates(warning) != null)
            FilledButton.icon(
              onPressed: () {
                final coordinates = _warningCoordinates(warning)!;
                Navigator.of(dialogContext).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WarningLocationScreen(
                      warning: warning,
                      coordinates: coordinates,
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.location_on_outlined),
              label: const Text('View location'),
            ),
        ],
      ),
    );
  }

  static LatLng? _warningCoordinates(Map<String, dynamic> warning) {
    final latitude = warning['lat'] ?? warning['latitude'];
    final longitude = warning['lon'] ?? warning['longitude'];
    final lat =
        latitude is num ? latitude.toDouble() : double.tryParse('$latitude');
    final lon =
        longitude is num ? longitude.toDouble() : double.tryParse('$longitude');
    if (lat == null || lon == null || lat.abs() > 90 || lon.abs() > 180)
      return null;
    return LatLng(lat, lon);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Weather & Warnings',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xff10353a),
                  ),
            ),
            if (onRefresh != null)
              IconButton(
                onPressed: refreshing ? null : onRefresh,
                tooltip: 'Refresh weather and warnings',
                icon: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 12),

        // Weather Card
        if (weather != null)
          Card(
            color: const Color(0xffe7f2fb),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.cloud_outlined,
                        size: 34,
                        color: Color(0xff2d6f9f),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${weather!['condition']}',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            if (weather!['location_name'] != null &&
                                weather!['location_name'].toString().isNotEmpty)
                              Text(
                                'Location: ${weather!['location_name']}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xff2d6f9f),
                                ),
                              ),
                            Text(
                              'Rainfall ${weather!['rainfall_mm']} mm • ${weather!['source']}',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (weather!['temp_celsius'] != null ||
                      weather!['humidity_percent'] != null ||
                      weather!['wind_speed_ms'] != null) ...[
                    const Divider(height: 20),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        if (weather!['temp_celsius'] != null)
                          Column(
                            children: [
                              const Text(
                                'Temperature',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                '${weather!['temp_celsius']?.toStringAsFixed(1)}°C',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        if (weather!['humidity_percent'] != null)
                          Column(
                            children: [
                              const Text(
                                'Humidity',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                '${weather!['humidity_percent']}%',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        if (weather!['wind_speed_ms'] != null)
                          Column(
                            children: [
                              const Text(
                                'Wind',
                                style:
                                    TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                              Text(
                                '${weather!['wind_speed_ms']?.toStringAsFixed(1)} m/s',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        const SizedBox(height: 12),

        // Warnings Section
        Text(
          'Active Warnings',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: const Color(0xff10353a),
              ),
        ),
        const SizedBox(height: 8),
        if (warnings.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.check_circle_outline, color: Colors.green),
              title: Text('No active warnings nearby.'),
              subtitle: Text('Conditions look clear within 5km of your area.'),
            ),
          )
        else
          ...warnings.map(
            (item) => Card(
              color: const Color(0xfffff2d6),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _showWarningDetails(
                    context, Map<String, dynamic>.from(item as Map)),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.warning_amber_rounded,
                            color: Color(0xffb45a00),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${item['title'] ?? item['type'] ?? 'Warning'} - ${item['severity'] ?? 'UNKNOWN'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (item['description'] != null) ...[
                        const SizedBox(height: 6),
                        Text('${item['description']}'),
                      ],
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 16,
                        runSpacing: 4,
                        children: [
                          Text(
                            'Radius: ${item['radius_km'] ?? 5} km',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                          if (item['source'] != null)
                            Text(
                              'Source: ${item['source']}',
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Tap for warning details and location',
                        style: TextStyle(fontSize: 12, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WarningDetailRow extends StatelessWidget {
  const _WarningDetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(value),
          ],
        ),
      );
}

class WarningLocationScreen extends StatelessWidget {
  const WarningLocationScreen({
    super.key,
    required this.warning,
    required this.coordinates,
  });

  final Map<String, dynamic> warning;
  final LatLng coordinates;

  @override
  Widget build(BuildContext context) {
    final title = '${warning['title'] ?? warning['type'] ?? 'Warning'}';
    return Scaffold(
      appBar: AppBar(title: const Text('Reported warning location')),
      body: FlutterMap(
        options: MapOptions(initialCenter: coordinates, initialZoom: 14),
        children: [
          TileLayer(
            urlTemplate: MapTileConfig.urlTemplate,
            userAgentPackageName: 'com.example.disaster_routing_mobile',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: coordinates,
                width: 56,
                height: 56,
                child: const Icon(
                  Icons.warning_rounded,
                  color: Color(0xffb45a00),
                  size: 46,
                ),
              ),
            ],
          ),
          Positioned(
            left: 16,
            right: 16,
            top: 16,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(title,
                    style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dedicated Emergency Facilities Panel
class EmergencyFacilitiesPanel extends StatelessWidget {
  const EmergencyFacilitiesPanel({
    super.key,
    required this.facilities,
    required this.onOpenFacility,
    this.onRefresh,
    this.refreshing = false,
  });

  final List<dynamic> facilities;
  final ValueChanged<Map<String, dynamic>> onOpenFacility;
  final VoidCallback? onRefresh;
  final bool refreshing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Emergency Facilities',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xff10353a),
                  ),
            ),
            if (onRefresh != null)
              IconButton(
                onPressed: refreshing ? null : onRefresh,
                tooltip: 'Refresh facilities',
                icon: refreshing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (facilities.isEmpty)
          const Card(
            child: ListTile(
              leading: Icon(Icons.location_searching),
              title: Text('No facilities found nearby'),
              subtitle: Text('Refresh after checking your location.'),
            ),
          )
        else
          ...facilities.take(10).map(
                (item) => Card(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  child: ListTile(
                    onTap: () {
                      print('🏥 Facility tapped: ${item['name']}');
                      onOpenFacility(Map<String, dynamic>.from(item as Map));
                    },
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xffdff3f1),
                      child: Icon(_getFacilityIconForPanel(
                          item['type'] as String? ?? 'FACILITY')),
                    ),
                    title: Text(
                      item['name'] as String,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${item['type']} • ${item['distance_km'] ?? '-'} km away',
                          style: const TextStyle(fontSize: 13),
                        ),
                        if (item['formatted_address'] != null &&
                            item['formatted_address'].toString().isNotEmpty)
                          Text(
                            '${item['formatted_address']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        if (item['contact'] != null)
                          Text(
                            'Contact: ${item['contact']}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                      ],
                    ),
                    trailing:
                        const Icon(Icons.navigation, color: Color(0xff2d6f9f)),
                  ),
                ),
              ),
      ],
    );
  }

  IconData _getFacilityIconForPanel(String type) {
    switch (type.toUpperCase()) {
      case 'HOSPITAL':
        return Icons.local_hospital_outlined;
      case 'POLICE':
        return Icons.local_police_outlined;
      case 'FIRE_STATION':
        return Icons.local_fire_department_outlined;
      case 'SHELTER':
        return Icons.home_outlined;
      default:
        return Icons.place_outlined;
    }
  }
}

class _EmergencyModeBanner extends StatelessWidget {
  const _EmergencyModeBanner();

  @override
  Widget build(BuildContext context) => Card(
        color: const Color(0xff8c1d18),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _PulseDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('EMERGENCY MODE',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 18)),
                    SizedBox(height: 4),
                    Text(
                        'Critical route risk detected. Prioritizing warnings, safer routing, and SOS.',
                        style: TextStyle(color: Colors.white, height: 1.3))
                  ],
                ),
              )
            ],
          ),
        ),
      );
}

class _PulseDot extends StatefulWidget {
  const _PulseDot();

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: Tween<double>(begin: 0.45, end: 1).animate(controller),
        child: const Icon(Icons.warning_rounded, color: Colors.white, size: 30),
      );
}

class _StatusMetric extends StatelessWidget {
  const _StatusMetric(
      {required this.icon,
      required this.label,
      required this.value,
      required this.color,
      this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: onTap != null
                  ? Border.all(color: color.withOpacity(0.3), width: 1)
                  : null),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              children: [
                Icon(icon, color: color, size: 22),
                if (onTap != null) ...[
                  const SizedBox(width: 4),
                  Icon(Icons.touch_app,
                      size: 12, color: color.withOpacity(0.5)),
                ],
              ],
            ),
            const SizedBox(height: 8),
            Text(label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.inkMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800))
          ]),
        ),
      );
}

class RouteTab extends StatelessWidget {
  const RouteTab(
      {super.key,
      required this.route,
      required this.incidents,
      required this.position,
      required this.journeyActive,
      required this.journeyProgress,
      required this.remainingMeters,
      required this.onStartJourney,
      required this.onEndJourney,
      required this.fullscreen,
      required this.onToggleFullscreen});
  final Map<String, dynamic>? route;
  final List<dynamic> incidents;
  final Position? position;
  final bool journeyActive;
  final double? journeyProgress;
  final double? remainingMeters;
  final Future<void> Function() onStartJourney;
  final Future<void> Function() onEndJourney;
  final bool fullscreen;
  final VoidCallback onToggleFullscreen;
  @override
  Widget build(BuildContext context) {
    final recommended = _recommendedRoute(route);
    if (recommended == null)
      return const Center(child: Text('Request a route from Home first.'));

    // Debug: Log route data
    print('🗺️ RouteTab rendering with route: ${route?.keys}');
    print('🗺️ Recommended route: ${recommended.keys}');
    print('🗺️ Geometry: ${recommended['geometry']}');

    final points = ((recommended['geometry'] as List?) ?? [])
        .map((point) {
          // Handle different geometry formats
          if (point is List && point.length >= 2) {
            return LatLng(
                (point[0] as num).toDouble(), (point[1] as num).toDouble());
          }
          return null;
        })
        .whereType<LatLng>()
        .toList();

    print('🗺️ Extracted ${points.length} points for map display');
    final progress = (journeyProgress ?? 0).clamp(0.0, 1.0);
    final remainingLabel = remainingMeters == null
        ? 'Waiting for GPS...'
        : '${(remainingMeters! / 1000).toStringAsFixed(1)} km remaining';
    final alternatives = (route?['alternatives'] as List?)
            ?.whereType<Map>()
            .map((item) => Map<String, dynamic>.from(item))
            .toList() ??
        const <Map<String, dynamic>>[];
    return Column(children: [
      Expanded(
          child: Stack(children: [
        FlutterMap(
            options: MapOptions(
                initialCenter: position == null
                    ? (points.isEmpty ? const LatLng(0, 0) : points.first)
                    : LatLng(position!.latitude, position!.longitude),
                initialZoom: 13),
            children: [
              TileLayer(
                  urlTemplate: MapTileConfig.urlTemplate,
                  userAgentPackageName: 'com.example.disaster_routing_mobile'),
              if (points.length > 1)
                PolylineLayer(polylines: [
                  Polyline(points: points, color: Colors.teal, strokeWidth: 5)
                ]),
              if (position != null)
                MarkerLayer(markers: [
                  Marker(
                      point: LatLng(position!.latitude, position!.longitude),
                      width: 42,
                      height: 42,
                      child: journeyActive
                          ? const _TrackingMarker()
                          : const Icon(Icons.my_location,
                              color: Colors.blue, size: 32))
                ]),
              if (incidents.isNotEmpty)
                MarkerLayer(
                    markers: incidents
                        .whereType<Map>()
                        .where((incident) => incident['status'] == 'ACTIVE')
                        .map((incident) {
                  final map = Map<String, dynamic>.from(incident);
                  final severity = '${map['severity']}'.toUpperCase();
                  final color = severity == 'CRITICAL' || severity == 'HIGH'
                      ? const Color(0xffb3261e)
                      : severity == 'MEDIUM'
                          ? const Color(0xffb45a00)
                          : const Color(0xff16734b);
                  return Marker(
                      point: LatLng((map['lat'] as num).toDouble(),
                          (map['lon'] as num).toDouble()),
                      width: 44,
                      height: 44,
                      child: _HazardMarker(color: color));
                }).toList())
            ]),
        Positioned(
            right: 16,
            bottom: 16,
            child: FloatingActionButton.small(
                heroTag: 'route-map-fullscreen',
                onPressed: onToggleFullscreen,
                tooltip: fullscreen ? 'Show route details' : 'Full screen map',
                child: Icon(
                    fullscreen ? Icons.fullscreen_exit : Icons.fullscreen))),
        Positioned(
            top: 16,
            left: 16,
            right: 16,
            child: Card(
                color: Colors.white.withValues(alpha: 0.94),
                child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      Icon(journeyActive ? Icons.navigation : Icons.route,
                          color: Theme.of(context).colorScheme.primary),
                      const SizedBox(width: 10),
                      Text(journeyActive ? 'Live navigation' : 'Safer route',
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text(journeyActive ? 'GPS active' : 'Risk-aware',
                          style: const TextStyle(fontSize: 12))
                    ]))))
      ])),
      if (!fullscreen)
        Expanded(
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  RouteSummary(route: recommended),
                  if ((route?['segments'] as List?)?.isNotEmpty ?? false)
                    _RouteRiskTimeline(
                        segments: (route!['segments'] as List)
                            .whereType<Map>()
                            .map((item) => Map<String, dynamic>.from(item))
                            .toList()),
                  if (alternatives.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('Compare other routes',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800))),
                    ...alternatives
                        .map((item) => _AlternativeRouteCard(route: item))
                  ],
                  if (journeyActive)
                    const Card(
                        color: Color(0xffdff3f1),
                        child: ListTile(
                            leading: Icon(Icons.verified_outlined),
                            title: Text('SAFE ARRIVAL IN PROGRESS',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            subtitle: Text(
                                'You are following the recommended route.'))),
                  if (journeyActive)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(remainingLabel,
                                  style:
                                      Theme.of(context).textTheme.titleMedium),
                              const SizedBox(height: 6),
                              LinearProgressIndicator(value: progress),
                              const SizedBox(height: 4),
                              Text(
                                  '${(progress * 100).round()}% route progress')
                            ])),
                  const SizedBox(height: 8),
                  SizedBox(
                      width: double.infinity,
                      child: journeyActive
                          ? FilledButton.icon(
                              onPressed: onEndJourney,
                              icon: const Icon(Icons.stop_circle_outlined),
                              label: const Text('End Journey'))
                          : FilledButton.icon(
                              onPressed: onStartJourney,
                              icon: const Icon(Icons.navigation),
                              label: const Text('Start Journey'))),
                  if (journeyActive)
                    Card(
                        color: const Color(0xffdff3f1),
                        child: Padding(
                            padding: const EdgeInsets.all(10),
                            child: Row(children: const [
                              Icon(Icons.gps_fixed, size: 18),
                              SizedBox(width: 8),
                              Text('LIVE GPS TRACKING ACTIVE',
                                  style: TextStyle(fontWeight: FontWeight.w800))
                            ])))
                ])))
    ]);
  }
}

class _TrackingMarker extends StatefulWidget {
  const _TrackingMarker();

  @override
  State<_TrackingMarker> createState() => _TrackingMarkerState();
}

class _TrackingMarkerState extends State<_TrackingMarker>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: controller,
        builder: (context, child) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
                width: 34 + controller.value * 12,
                height: 34 + controller.value * 12,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.blue.withValues(alpha: 0.16))),
            const Icon(Icons.navigation, color: Colors.blue, size: 28),
          ],
        ),
      );
}

class RouteSummary extends StatelessWidget {
  const RouteSummary({super.key, required this.route});
  final Map<String, dynamic> route;
  @override
  Widget build(BuildContext context) {
    // Debug logging
    print('📊 RouteSummary rendering with route keys: ${route.keys}');
    print('📊 Distance: ${route['distance_km']}');
    print('📊 ETA: ${route['eta_minutes']}');

    // Extract distance and duration with fallback to handle different API response structures
    final distanceKm = route['distance_km'] is num
        ? (route['distance_km'] as num).toDouble()
        : 0.0;
    final etaMinutes =
        route['eta_minutes'] is num ? (route['eta_minutes'] as num).toInt() : 0;

    // Extract risk information with safe navigation
    final riskMap =
        route['risk'] is Map ? route['risk'] as Map<String, dynamic> : {};
    final risk = '${riskMap['overall'] ?? 'UNKNOWN'}'.toUpperCase();
    final confidence = riskMap['confidence'] is num
        ? (riskMap['confidence'] as num).toInt()
        : 0;

    final riskColor = risk.contains('HIGH') || risk.contains('CRITICAL')
        ? const Color(0xffb3261e)
        : risk.contains('MEDIUM') || risk.contains('MODERATE')
            ? const Color(0xffb45a00)
            : const Color(0xff16734b);

    // Extract warnings safely
    final warnings =
        route['warnings'] is List ? route['warnings'] as List : <dynamic>[];

    // Extract reason safely
    final reason =
        route['reason']?.toString() ?? 'Route calculated successfully';

    // Handle zero values case
    if (distanceKm == 0.0 && etaMinutes == 0) {
      print('⚠️ RouteSummary has zero distance and ETA');
    }

    return Card(
        margin: const EdgeInsets.only(top: 16),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('RECOMMENDED ROUTE',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.bold))),
                Chip(
                    avatar:
                        Icon(Icons.shield_outlined, size: 16, color: riskColor),
                    label: Text(risk),
                    side: BorderSide.none,
                    backgroundColor: riskColor.withValues(alpha: 0.12))
              ]),
              const SizedBox(height: 8),
              Text('${distanceKm.toStringAsFixed(1)} km  •  $etaMinutes min',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              Text('Confidence: $confidence%'),
              const SizedBox(height: 8),
              Text(reason),
              ...(warnings.map((warning) => Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        size: 18, color: Color(0xffb45a00)),
                    const SizedBox(width: 6),
                    Expanded(child: Text('$warning'))
                  ]))))
            ])));
  }
}

class _HazardMarker extends StatelessWidget {
  const _HazardMarker({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Active hazard location',
        child: DecoratedBox(
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18), shape: BoxShape.circle),
          child: Center(
              child: Icon(Icons.warning_rounded, color: color, size: 28)),
        ),
      );
}

class _AlternativeRouteCard extends StatelessWidget {
  const _AlternativeRouteCard({required this.route});
  final Map<String, dynamic> route;

  @override
  Widget build(BuildContext context) {
    // Extract risk information safely
    final riskMap =
        route['risk'] is Map ? route['risk'] as Map<String, dynamic> : null;
    final risk =
        '${riskMap?['overall'] ?? route['risk'] ?? 'UNKNOWN'}'.toUpperCase();

    final color = risk.contains('HIGH') || risk.contains('CRITICAL')
        ? const Color(0xffb3261e)
        : risk.contains('MEDIUM') || risk.contains('MODERATE')
            ? const Color(0xffb45a00)
            : const Color(0xff16734b);

    // Extract distance and duration safely
    final distanceKm = route['distance_km'] is num
        ? (route['distance_km'] as num).toDouble()
        : null;
    final etaMinutes = route['eta_minutes'] is num
        ? (route['eta_minutes'] as num).toInt()
        : null;

    // Extract warnings count safely
    final warningsCount =
        route['warnings'] is List ? (route['warnings'] as List).length : 0;

    return Card(
        margin: const EdgeInsets.only(top: 8),
        child: ListTile(
            leading: Icon(Icons.alt_route, color: color),
            title: Text(
                '${distanceKm?.toStringAsFixed(1) ?? '-'} km • ${etaMinutes ?? '-'} min',
                style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text('Risk: $risk • $warningsCount warnings'),
            trailing: const Icon(Icons.chevron_right)));
  }
}

class _RouteRiskTimeline extends StatelessWidget {
  const _RouteRiskTimeline({required this.segments});
  final List<Map<String, dynamic>> segments;

  Color _color(String risk) {
    final value = risk.toUpperCase();
    if (value == 'CRITICAL' || value == 'HIGH') return const Color(0xffb3261e);
    if (value == 'MEDIUM' || value == 'MODERATE')
      return const Color(0xffb45a00);
    return const Color(0xff16734b);
  }

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(top: 12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Route risk timeline',
                  style: TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 10),
              ...segments.asMap().entries.map((entry) {
                final segment = entry.value;
                final risk =
                    '${segment['flood_risk'] ?? segment['risk'] ?? 'UNKNOWN'}';
                return Row(children: [
                  Icon(Icons.circle, size: 14, color: _color(risk)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(
                          '${segment['road_name'] ?? segment['road_id'] ?? 'Road segment'} • ${risk.toUpperCase()}')),
                  if (entry.key < segments.length - 1) const SizedBox(width: 0)
                ]);
              })
            ],
          ),
        ),
      );
}

class SituationTab extends StatefulWidget {
  const SituationTab(
      {super.key,
      required this.api,
      required this.position,
      this.active = false,
      this.onOpenFacility});
  final ApiService api;
  final Position? position;
  final bool active;
  final ValueChanged<Map<String, dynamic>>? onOpenFacility;

  @override
  State<SituationTab> createState() => _SituationTabState();
}

class _SituationTabState extends State<SituationTab> {
  List<dynamic> warnings = [];
  List<dynamic> facilities = [];
  Map<String, dynamic>? weather;
  Map<String, dynamic>? traffic;
  String? message;
  bool loading = true;
  bool refreshingWeather = false;
  bool refreshingFacilities = false;
  bool refreshingTraffic = false;

  @override
  void didUpdateWidget(covariant SituationTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position ||
        (widget.active && !oldWidget.active)) {
      refresh();
    }
  }

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    if (mounted)
      setState(() {
        loading = true;
        message = null;
      });
    try {
      final currentPosition = widget.position;
      if (currentPosition == null) {
        if (mounted) {
          setState(() {
            warnings = [];
            facilities = [];
            weather = null;
            traffic = null;
            message =
                'Location is unavailable. Enable location to load live situation data.';
          });
        }
        return;
      }
      final latitude = currentPosition.latitude;
      final longitude = currentPosition.longitude;
      final values = await Future.wait([
        widget.api.nearbyWarnings(lat: latitude, lon: longitude),
        widget.api.facilities(lat: latitude, lon: longitude),
        widget.api.weather(lat: latitude, lon: longitude),
        widget.api.traffic(),
      ]);
      if (mounted)
        setState(() {
          warnings = values[0] as List<dynamic>;
          facilities = values[1] as List<dynamic>;
          weather = values[2] as Map<String, dynamic>;
          traffic = values[3] as Map<String, dynamic>;
        });
    } catch (error) {
      if (mounted)
        setState(() => message =
            'Live situation data unavailable. Refresh after reconnecting.');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> refreshWeatherAndWarnings() async {
    if (refreshingWeather) return;
    final currentPosition = widget.position;
    if (currentPosition == null) return;
    setState(() => refreshingWeather = true);
    try {
      final latitude = currentPosition.latitude;
      final longitude = currentPosition.longitude;
      final values = await Future.wait([
        widget.api.nearbyWarnings(lat: latitude, lon: longitude),
        widget.api.weather(lat: latitude, lon: longitude),
      ]);
      if (mounted) {
        setState(() {
          warnings = values[0] as List<dynamic>;
          weather = values[1] as Map<String, dynamic>;
          refreshingWeather = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => refreshingWeather = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Failed to refresh weather and warnings: $error')),
        );
      }
    }
  }

  Future<void> refreshFacilities() async {
    if (refreshingFacilities) return;
    final currentPosition = widget.position;
    if (currentPosition == null) return;
    setState(() => refreshingFacilities = true);
    try {
      final latitude = currentPosition.latitude;
      final longitude = currentPosition.longitude;
      final updatedFacilities =
          await widget.api.facilities(lat: latitude, lon: longitude);
      if (mounted) {
        setState(() {
          facilities = updatedFacilities;
          refreshingFacilities = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => refreshingFacilities = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh facilities: $error')),
        );
      }
    }
  }

  Future<void> refreshTraffic() async {
    if (refreshingTraffic) return;
    setState(() => refreshingTraffic = true);
    try {
      final updatedTraffic = await widget.api.traffic();
      if (mounted) {
        setState(() {
          traffic = updatedTraffic;
          refreshingTraffic = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => refreshingTraffic = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to refresh traffic: $error')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Situation',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Text('Nearby conditions and emergency services')
              ]),
              IconButton(
                  onPressed: refresh,
                  tooltip: 'Refresh situation data',
                  icon: const Icon(Icons.refresh))
            ]),
            if (message != null)
              Card(
                color: const Color(0xfffff2d6),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(message!,
                      style: const TextStyle(color: Color(0xff713a00))),
                ),
              ),
            const SizedBox(height: 16),

            // Use dedicated Weather & Warnings Panel
            WeatherWarningsPanel(
              weather: weather,
              warnings: warnings,
              onRefresh: refreshWeatherAndWarnings,
              refreshing: refreshingWeather,
            ),

            const SizedBox(height: 20),

            // Use dedicated Emergency Facilities Panel
            EmergencyFacilitiesPanel(
              facilities: facilities,
              onOpenFacility: widget.onOpenFacility ?? (_) {},
              onRefresh: refreshFacilities,
              refreshing: refreshingFacilities,
            ),

            const SizedBox(height: 16),

            // Traffic conditions (separate section)
            Card(
              child: ListTile(
                leading: const Icon(Icons.traffic_outlined),
                title: const Text('Traffic conditions'),
                subtitle: Text(traffic != null
                    ? '${traffic!.length} road entries are informing route safety.'
                    : 'Loading traffic data...'),
                trailing: IconButton(
                  onPressed: refreshingTraffic ? null : refreshTraffic,
                  icon: refreshingTraffic
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  tooltip: 'Refresh traffic data',
                ),
              ),
            ),
          ]),
    );
  }
}

class ReportsTab extends StatefulWidget {
  const ReportsTab(
      {super.key,
      required this.api,
      required this.position,
      this.active = false,
      this.onReportSubmitted});
  final ApiService api;
  final Position? position;
  final bool active;
  final VoidCallback? onReportSubmitted;
  @override
  State<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends State<ReportsTab> {
  final description = TextEditingController();
  String type = 'Flood';
  String? message;
  bool sending = false;
  List<dynamic> reportHistory = [];
  XFile? photo;

  @override
  void didUpdateWidget(covariant ReportsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position ||
        (widget.active && !oldWidget.active)) {
      loadReports();
    }
  }

  @override
  void initState() {
    super.initState();
    loadReports();
  }

  Future<void> loadReports() async {
    try {
      final values = await widget.api.myReports();
      if (mounted) setState(() => reportHistory = values);
    } catch (_) {}
  }

  @override
  void dispose() {
    description.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (widget.position == null) {
      setState(() => message = 'Enable location before submitting a report.');
      return;
    }
    if (description.text.trim().length < 3) {
      setState(() => message = 'Describe the hazard in at least 3 characters.');
      return;
    }
    setState(() {
      sending = true;
      message = null;
    });
    try {
      final result = await widget.api.submitReport(
          type: type,
          lat: widget.position!.latitude,
          lon: widget.position!.longitude,
          description: description.text.trim(),
          photoData:
              photo == null ? null : base64Encode(await photo!.readAsBytes()));
      if (mounted) {
        description.clear();
        photo = null;
        await HapticFeedback.mediumImpact();
        setState(() => message = result['status'] == 'QUEUED_OFFLINE'
            ? 'Report queued offline and will sync after reconnection.'
            : 'Report submitted as PENDING for authority review.');
        await loadReports();
        // Refresh incidents after report submission
        widget.onReportSubmitted?.call();
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    }
    if (mounted) setState(() => sending = false);
  }

  Future<void> attachPhoto() async {
    final selected = await ImagePicker().pickImage(
        source: ImageSource.camera, imageQuality: 75, maxWidth: 1600);
    if (mounted && selected != null) setState(() => photo = selected);
  }

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Report a hazard',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Your report helps responders keep roads safer.'),
          const SizedBox(height: 12),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Align(
                        alignment: Alignment.centerLeft,
                        child: Text('What happened?',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800))),
                    const SizedBox(height: 8),
                    Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          'Flood',
                          'Landslide',
                          'Blocked Road',
                          'Fallen Tree',
                          'Damaged Road',
                          'Other'
                        ]
                            .map((value) => ChoiceChip(
                                label: Text(value),
                                selected: type == value,
                                onSelected: (_) =>
                                    setState(() => type = value)))
                            .toList()),
                    const SizedBox(height: 12),
                    TextField(
                        controller: description,
                        minLines: 4,
                        maxLines: 6,
                        decoration: const InputDecoration(
                            labelText: 'Describe the hazard')),
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.my_location, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(widget.position == null
                              ? 'Location unavailable'
                              : 'Location attached to this report'))
                    ]),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                        onPressed: attachPhoto,
                        icon: const Icon(Icons.camera_alt_outlined),
                        label: Text(photo == null
                            ? 'Add photo evidence'
                            : 'Replace photo')),
                    if (photo != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 10),
                          child: FutureBuilder<Uint8List>(
                              future: photo!.readAsBytes(),
                              builder: (context, snapshot) => snapshot.hasData
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(snapshot.data!,
                                          height: 150,
                                          width: double.infinity,
                                          fit: BoxFit.cover))
                                  : const LinearProgressIndicator())),
                    const SizedBox(height: 14),
                    SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                            onPressed: sending ? null : submit,
                            icon: const Icon(Icons.send),
                            label: Text(
                                sending ? 'Submitting...' : 'Submit report')))
                  ]))),
          if (message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12), child: Text(message!)),
          const SizedBox(height: 20),
          Text('My report status',
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800)),
          if (reportHistory.isEmpty)
            const Card(
                child: ListTile(
                    leading: Icon(Icons.assignment_outlined),
                    title: Text('No reports submitted yet'),
                    subtitle: Text('Submitted hazards will appear here.'))),
          ...reportHistory.map((item) => Card(
              child: ListTile(
                  onTap: () => _showReportDetails(
                      context, Map<String, dynamic>.from(item as Map)),
                  leading: item['photo_data'] != null
                      ? const Icon(Icons.photo_camera_outlined)
                      : const Icon(Icons.assignment_outlined),
                  title: Text('${item['problem_type']} - ${item['status']}'),
                  subtitle: Text(item['description'] as String)))),
        ],
      );
}

class OfflineTab extends StatefulWidget {
  const OfflineTab(
      {super.key,
      required this.api,
      required this.route,
      required this.source,
      required this.destination,
      required this.mode,
      required this.onOpen});
  final ApiService api;
  final Map<String, dynamic>? route;
  final String source;
  final String destination;
  final String mode;
  final ValueChanged<Map<String, dynamic>> onOpen;
  @override
  State<OfflineTab> createState() => _OfflineTabState();
}

class _OfflineTabState extends State<OfflineTab> {
  final store = const SavedRouteStore();
  late Future<List<Map<String, dynamic>>> savedRoutes;
  int queuedReports = 0;
  String? lastSync;
  bool syncing = false;

  @override
  void initState() {
    super.initState();
    savedRoutes = store.list();
    loadSyncStatus();
  }

  void refresh() => setState(() => savedRoutes = store.list());

  Future<void> loadSyncStatus() async {
    final count = await widget.api.queuedReportCount();
    final timestamp = await widget.api.cachedSyncTime();
    if (mounted)
      setState(() {
        queuedReports = count;
        lastSync = timestamp;
      });
  }

  Future<void> syncNow() async {
    if (syncing) return;
    setState(() => syncing = true);
    try {
      await widget.api.sync();
      await widget.api.flushQueuedReports();
      await loadSyncStatus();
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Offline data synchronized.')));
    } catch (_) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content:
                Text('Sync unavailable. Saved data remains on this device.')));
    } finally {
      if (mounted) setState(() => syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: savedRoutes,
      builder: (context, snapshot) => ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text('Offline mode',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          const Text('Saved routes remain available when the network is weak.'),
          const SizedBox(height: 16),
          Card(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Row(children: [
                      const Icon(Icons.sync, color: Color(0xff0f6b66)),
                      const SizedBox(width: 10),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('Synchronization',
                                style: TextStyle(fontWeight: FontWeight.w800)),
                            Text(queuedReports == 0
                                ? 'All reports sent'
                                : '$queuedReports report(s) waiting to sync'),
                            if (lastSync != null)
                              Text(
                                  'Last sync: ${lastSync!.replaceFirst('T', ' ').split('.').first}',
                                  style: const TextStyle(fontSize: 12))
                          ])),
                      IconButton(
                          onPressed: syncing ? null : syncNow,
                          tooltip: 'Sync now',
                          icon: syncing
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.refresh))
                    ]),
                    const SizedBox(height: 10),
                    const Row(children: [
                      Expanded(child: _SyncCheck(label: 'Saved routes')),
                      Expanded(child: _SyncCheck(label: 'Queued reports')),
                      Expanded(child: _SyncCheck(label: 'Road data'))
                    ])
                  ]))),
          const SizedBox(height: 16),
          Card(
            color: const Color(0xfffff2d6),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: const [
                Icon(Icons.offline_bolt, color: Color(0xffb45a00), size: 30),
                SizedBox(width: 12),
                Expanded(
                    child: Text(
                        'Offline data can be stale. Follow official instructions and verify conditions when possible.'))
              ]),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Row(children: [
                    Icon(Icons.map_outlined),
                    SizedBox(width: 8),
                    Text('Saved route cache',
                        style: TextStyle(fontWeight: FontWeight.w800))
                  ]),
                  const SizedBox(height: 12),
                  if (widget.route != null)
                    FilledButton.icon(
                        onPressed: () async {
                          final recommended = _recommendedRoute(widget.route);
                          if (recommended == null) return;
                          await store.save(recommended,
                              source: widget.source,
                              destination: widget.destination,
                              mode: widget.mode);
                          refresh();
                          if (context.mounted)
                            ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                    content: Text(
                                        'Recommended route saved for offline use.')));
                        },
                        icon: const Icon(Icons.download),
                        label: const Text('Save current route offline')),
                  const SizedBox(height: 8),
                  if (snapshot.connectionState == ConnectionState.waiting)
                    const CircularProgressIndicator()
                  else if ((snapshot.data ?? []).isEmpty)
                    const Text('No saved offline routes yet.')
                  else
                    ...snapshot.data!.map((item) => Card(
                        child: ListTile(
                            title: Text(
                                '${item['source']} to ${item['destination']}'),
                            subtitle: Text('Mode: ${item['mode']}'),
                            onTap: () => widget.onOpen(
                                Map<String, dynamic>.from(
                                    item['route'] as Map)),
                            trailing: IconButton(
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  await store.remove(item['id'] as String);
                                  if (mounted) refresh();
                                })))),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncCheck extends StatelessWidget {
  const _SyncCheck({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(children: [
        const Icon(Icons.check_circle, size: 16, color: Color(0xff16734b)),
        const SizedBox(width: 4),
        Expanded(child: Text(label, style: const TextStyle(fontSize: 11)))
      ]);
}

class ProfileTab extends StatefulWidget {
  const ProfileTab({
    super.key,
    required this.user,
    required this.onLogout,
    this.themeMode = ThemeMode.system,
    this.onThemeModeChanged,
  });

  final Map<String, dynamic> user;
  final Future<void> Function() onLogout;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode>? onThemeModeChanged;

  @override
  State<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  bool notificationsEnabled = true;
  bool locationEnabled = true;
  bool largeText = false;

  @override
  Widget build(BuildContext context) {
    final selectedTheme = widget.themeMode == ThemeMode.dark
        ? ThemeMode.dark
        : ThemeMode.light;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 42)),
        const SizedBox(height: 12),
        Center(
            child: Text(widget.user['name'] as String,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800))),
        Center(
            child: Text(widget.user['email'] as String,
                style: const TextStyle(color: Color(0xff527276)))),
        const SizedBox(height: 20),
        Text('Account',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Card(
            child: ListTile(
                leading: const Icon(Icons.verified_user_outlined),
                title: const Text('Account role'),
                subtitle: Text(widget.user['role'] as String))),
        Card(
            child: SwitchListTile(
                secondary: const Icon(Icons.notifications_outlined),
                title: const Text('Emergency notifications'),
                subtitle: const Text('Warnings and route updates'),
                value: notificationsEnabled,
                onChanged: (value) =>
                    setState(() => notificationsEnabled = value))),
        Card(
            child: SwitchListTile(
                secondary: const Icon(Icons.location_on_outlined),
                title: const Text('Location services'),
                subtitle: const Text('Routing, warnings, and SOS location'),
                value: locationEnabled,
                onChanged: (value) => setState(() => locationEnabled = value))),
        Text('Safety',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        const Card(
            child: ListTile(
                leading: Icon(Icons.info_outline),
                title: Text('Safety note'),
                subtitle: Text(
                    'Authority data and road conditions can change. Follow official emergency instructions.'))),
        Text('Accessibility',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Card(
            child: SwitchListTile(
                secondary: const Icon(Icons.text_fields),
                title: const Text('Larger text'),
                subtitle: const Text('Increase text size for readability'),
                value: largeText,
                onChanged: (value) => setState(() => largeText = value))),
        Text('Appearance',
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800)),
        Card(
          child: Column(
            children: [
              const ListTile(
                leading: Icon(Icons.dark_mode_outlined),
                title: Text('Theme'),
                subtitle: Text('Choose your display mode'),
                contentPadding: EdgeInsets.zero,
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.light,
                groupValue: selectedTheme,
                title: const Text('Light'),
                secondary: const Icon(Icons.light_mode_outlined),
                onChanged: (mode) {
                  if (mode != null) widget.onThemeModeChanged?.call(mode);
                },
              ),
              RadioListTile<ThemeMode>(
                value: ThemeMode.dark,
                groupValue: selectedTheme,
                title: const Text('Dark'),
                secondary: const Icon(Icons.dark_mode_outlined),
                onChanged: (mode) {
                  if (mode != null) widget.onThemeModeChanged?.call(mode);
                },
              ),
            ],
          ),
        ),
        const Card(
            child: ListTile(
                leading: Icon(Icons.contacts_outlined),
                title: Text('Emergency contacts'),
                subtitle:
                    Text('Add trusted contacts for future SOS notifications.'),
                trailing: Icon(Icons.chevron_right))),
        const SizedBox(height: 8),
        OutlinedButton.icon(
            onPressed: widget.onLogout,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'))
      ],
    );
  }
}

Future<void> _showReportDetails(
    BuildContext context, Map<String, dynamic> report) async {
  Uint8List? imageBytes;
  final rawPhoto = report['photo_data'];
  if (rawPhoto is String && rawPhoto.isNotEmpty) {
    try {
      imageBytes = base64Decode(rawPhoto.contains(',')
          ? rawPhoto.substring(rawPhoto.indexOf(',') + 1)
          : rawPhoto);
    } catch (_) {
      imageBytes = null;
    }
  }
  await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
            title: Text(
                '${report['problem_type'] ?? 'Report'} - ${report['status'] ?? 'UNKNOWN'}'),
            content: SingleChildScrollView(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                  Text(report['description']?.toString() ??
                      'No description provided.'),
                  const SizedBox(height: 12),
                  Text('Confidence: ${report['confidence'] ?? 0}%'),
                  Text(
                      'Location: ${report['lat'] ?? '-'}, ${report['lon'] ?? '-'}'),
                  Text('Created: ${report['created_at'] ?? '-'}'),
                  if (imageBytes != null) ...[
                    const SizedBox(height: 12),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(imageBytes, fit: BoxFit.contain))
                  ]
                ])),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Close'))
            ],
          ));
}

class EmergencyTab extends StatefulWidget {
  const EmergencyTab(
      {super.key,
      required this.api,
      required this.position,
      this.active = false,
      this.onOpenFacility});
  final ApiService api;
  final Position? position;
  final bool active;
  final ValueChanged<Map<String, dynamic>>? onOpenFacility;
  @override
  State<EmergencyTab> createState() => _EmergencyTabState();
}

class _EmergencyTabState extends State<EmergencyTab> {
  String? message;
  List<dynamic> facilities = [];
  bool sending = false;
  double sosProgress = 0;
  bool refreshingFacilities = false;

  @override
  void didUpdateWidget(covariant EmergencyTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.position != oldWidget.position ||
        (widget.active && !oldWidget.active)) {
      loadFacilities();
    }
  }

  @override
  void initState() {
    super.initState();
    loadFacilities();
  }

  Future<void> loadFacilities() async {
    if (refreshingFacilities) return;
    setState(() => refreshingFacilities = true);
    try {
      final values = await Future.wait([
        widget.api.facilities(
            lat: widget.position?.latitude,
            lon: widget.position?.longitude,
            kind: 'SHELTER')
      ]);
      if (mounted) {
        setState(() {
          facilities = values.expand((items) => items).toList();
          refreshingFacilities = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => refreshingFacilities = false);
      }
    }
  }

  Future<void> sendSos() async {
    if (sending) return;
    if (widget.position == null) {
      setState(() => message = 'Location is required for SOS.');
      return;
    }
    setState(() {
      sending = true;
      sosProgress = 0.25;
      message = 'Sending emergency information...';
    });
    await HapticFeedback.heavyImpact();
    try {
      final value = await widget.api
          .sos(widget.position!.latitude, widget.position!.longitude);
      if (mounted) {
        final shelter = value['nearest_safe_shelter'] as Map<String, dynamic>?;
        setState(() {
          sosProgress = 1;
          message = shelter == null
              ? 'SOS recorded. No safe shelter is currently available.'
              : 'SOS recorded. Nearest safe shelter: ${shelter['name']}';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text('Emergency assistance',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        const Text(
            'Send your location to the emergency service and find shelter.'),
        const SizedBox(height: 18),
        Card(
            color: const Color(0xffffe4e1),
            child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(children: [
                  const Icon(Icons.sos, color: Color(0xffb3261e), size: 54),
                  const SizedBox(height: 8),
                  const Text('SOS',
                      style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          color: Color(0xff8c1d18))),
                  const SizedBox(height: 4),
                  Text(
                      widget.position == null
                          ? 'Location unavailable'
                          : 'Location ready',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  const Text('Press and hold for 2 seconds to activate',
                      style: TextStyle(fontSize: 12)),
                  const SizedBox(height: 12),
                  SizedBox(
                      width: double.infinity,
                      height: 64,
                      child: GestureDetector(
                          onLongPress: sendSos,
                          child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xffb3261e)),
                              onPressed: null,
                              icon: sending
                                  ? const SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                          color: Colors.white,
                                          strokeWidth: 3,
                                          value: null))
                                  : const Icon(Icons.sos),
                              label: Text(sending
                                  ? 'SOS ACTIVATING'
                                  : 'HOLD TO SEND SOS')))),
                  if (sending || sosProgress == 1)
                    Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(
                            value: sosProgress == 1 ? 1 : null))
                ]))),
        if (message != null)
          Card(
              color: const Color(0xffdff3f1),
              child: Padding(
                  padding: const EdgeInsets.all(12), child: Text(message!))),
        const SizedBox(height: 20),

        // Use dedicated Emergency Facilities Panel
        EmergencyFacilitiesPanel(
          facilities: facilities,
          onOpenFacility: widget.onOpenFacility ?? (_) {},
          onRefresh: loadFacilities,
          refreshing: refreshingFacilities,
        ),
      ]);
}

class AuthorityTab extends StatefulWidget {
  const AuthorityTab({super.key, required this.api});
  final ApiService api;
  @override
  State<AuthorityTab> createState() => _AuthorityTabState();
}

class _AuthorityTabState extends State<AuthorityTab> {
  List<dynamic> reports = [];
  List<dynamic> closures = [];
  List<dynamic> incidents = [];
  StreamSubscription<Map<String, dynamic>>? incidentEvents;
  Timer? incidentReconnect;
  bool loading = true;
  String? message;
  final roadId = TextEditingController(text: 'D');
  final reason = TextEditingController(text: 'Flooding');
  String severity = 'HIGH';

  // Admin creation form state
  final adminName = TextEditingController();
  final adminEmail = TextEditingController();
  final adminPassword = TextEditingController();
  String adminRole = 'ADMIN';
  bool creatingAdmin = false;

  @override
  void initState() {
    super.initState();
    refresh();
    connectIncidentStream();
  }

  @override
  void dispose() {
    incidentEvents?.cancel();
    incidentReconnect?.cancel();
    roadId.dispose();
    reason.dispose();
    adminName.dispose();
    adminEmail.dispose();
    adminPassword.dispose();
    super.dispose();
  }

  void connectIncidentStream() {
    incidentReconnect?.cancel();
    incidentEvents?.cancel();
    incidentEvents = widget.api.incidentUpdates().listen((event) {
      final incident = event['incident'];
      if (!mounted || incident is! Map) return;
      final updated = Map<String, dynamic>.from(incident);
      setState(() {
        final index =
            incidents.indexWhere((item) => item['id'] == updated['id']);
        if (index == -1) {
          incidents = [updated, ...incidents];
        } else {
          incidents = [...incidents]..[index] = updated;
        }
      });
    },
        onDone: scheduleIncidentReconnect,
        onError: (_) => scheduleIncidentReconnect());
  }

  void scheduleIncidentReconnect() {
    if (!mounted || incidentReconnect?.isActive == true) return;
    incidentReconnect =
        Timer(const Duration(seconds: 5), connectIncidentStream);
  }

  Future<void> refresh() async {
    setState(() => loading = true);
    try {
      final values = await Future.wait([
        widget.api.reports(),
        widget.api.closures(),
        widget.api.incidents()
      ]);
      if (mounted)
        setState(() {
          reports = values[0];
          closures = values[1];
          incidents = values[2];
          message = null;
        });
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> review(String id, bool verify) async {
    try {
      await widget.api.reviewReport(id, verify);
      // Only refresh reports, not the entire page
      final updatedReports = await widget.api.reports();
      if (mounted) {
        setState(() {
          reports = updatedReports;
          message = verify
              ? 'Report verified successfully'
              : 'Report rejected successfully';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    }
  }

  Future<void> closeRoad() async {
    try {
      await widget.api.createClosure(
          roadId: roadId.text.trim(),
          reason: reason.text.trim(),
          severity: severity);
      if (mounted) {
        setState(
            () => message = 'Closure saved and will affect future routes.');
        await refresh();
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    }
  }

  Future<void> resolveIncident(String incidentId) async {
    try {
      await widget.api.resolveIncident(incidentId);
      // Only refresh incidents, not the entire page
      final updatedIncidents = await widget.api.incidents();
      if (mounted) {
        setState(() {
          incidents = updatedIncidents;
          message = 'Incident deactivated and removed from active warnings.';
        });
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    }
  }

  Future<void> createAdminAccount() async {
    if (adminName.text.trim().length < 2 ||
        adminEmail.text.trim().length < 5 ||
        adminPassword.text.length < 8) {
      setState(() => message =
          'Enter a name, valid email, and password of at least 8 characters.');
      return;
    }
    setState(() => creatingAdmin = true);
    try {
      await widget.api.createAdmin(
        name: adminName.text.trim(),
        email: adminEmail.text.trim(),
        password: adminPassword.text,
        role: adminRole,
      );
      if (mounted) {
        setState(() {
          message = 'Admin account created successfully.';
          adminName.clear();
          adminEmail.clear();
          adminPassword.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Admin account created successfully.')),
        );
      }
    } catch (exception) {
      if (mounted) setState(() => message = exception.toString());
    } finally {
      if (mounted) setState(() => creatingAdmin = false);
    }
  }

  List<dynamic> _sortReports(List<dynamic> reports) {
    // Separate pending and non-pending reports
    final pending = <dynamic>[];
    final processed = <dynamic>[];

    for (final report in reports) {
      if (report['status'] == 'PENDING') {
        pending.add(report);
      } else {
        processed.add(report);
      }
    }

    // Sort pending reports by creation time (newest first for priority)
    pending.sort((a, b) {
      final aTime = a['created_at'] as String? ?? '';
      final bTime = b['created_at'] as String? ?? '';
      return bTime.compareTo(aTime); // Newest first
    });

    // Sort processed reports by creation time (FIFO - oldest first)
    processed.sort((a, b) {
      final aTime = a['created_at'] as String? ?? '';
      final bTime = b['created_at'] as String? ?? '';
      return aTime.compareTo(bTime); // Oldest first (FIFO)
    });

    // Combine: pending on top, processed at bottom
    return [...pending, ...processed];
  }

  @override
  Widget build(BuildContext context) {
    if (loading) return const Center(child: CircularProgressIndicator());
    final pending = reports.where((item) => item['status'] == 'PENDING').length;
    return RefreshIndicator(
      onRefresh: refresh,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Authority dashboard',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
                child: _Metric(
                    label: 'Pending reports',
                    value: '$pending',
                    color: Colors.orange)),
            const SizedBox(width: 8),
            Expanded(
                child: _Metric(
                    label: 'Active closures',
                    value: '${closures.length}',
                    color: Colors.red))
          ]),
          const SizedBox(height: 16),
          const Text('Create road closure',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: roadId,
              decoration: const InputDecoration(
                  labelText: 'Road ID', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: reason,
              decoration: const InputDecoration(
                  labelText: 'Reason', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
              initialValue: severity,
              decoration: const InputDecoration(
                  labelText: 'Severity', border: OutlineInputBorder()),
              items: ['LOW', 'MEDIUM', 'HIGH', 'CRITICAL']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => severity = value!)),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: closeRoad,
              icon: const Icon(Icons.block),
              label: const Text('Create closure')),
          if (message != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child:
                    Text(message!, style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 16),
          const Text('Create admin account',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(
              controller: adminName,
              decoration: const InputDecoration(
                  labelText: 'Admin name', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: adminEmail,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                  labelText: 'Admin email', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          TextField(
              controller: adminPassword,
              obscureText: true,
              decoration: const InputDecoration(
                  labelText: 'Admin password', border: OutlineInputBorder())),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
              initialValue: adminRole,
              decoration: const InputDecoration(
                  labelText: 'Role', border: OutlineInputBorder()),
              items: ['ADMIN', 'AUTHORITY']
                  .map((value) =>
                      DropdownMenuItem(value: value, child: Text(value)))
                  .toList(),
              onChanged: (value) => setState(() => adminRole = value!)),
          const SizedBox(height: 8),
          FilledButton.icon(
              onPressed: creatingAdmin ? null : createAdminAccount,
              icon: const Icon(Icons.person_add),
              label: Text(creatingAdmin
                  ? 'Creating account...'
                  : 'Create admin account')),
          const SizedBox(height: 16),
          const Text('Report review',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ..._sortReports(reports).map((item) => Card(
              child: ListTile(
                  onTap: () => _showReportDetails(
                      context, Map<String, dynamic>.from(item as Map)),
                  title: Text('${item['problem_type']} - ${item['status']}'),
                  subtitle: Text(item['description'] as String),
                  trailing: item['status'] == 'PENDING'
                      ? Wrap(children: [
                          IconButton(
                              onPressed: () =>
                                  review(item['id'] as String, true),
                              icon: const Icon(Icons.verified,
                                  color: Colors.green)),
                          IconButton(
                              onPressed: () =>
                                  review(item['id'] as String, false),
                              icon: const Icon(Icons.close, color: Colors.red))
                        ])
                      : null))),
          const SizedBox(height: 16),
          const Text('Active road closures',
              style: TextStyle(fontWeight: FontWeight.bold)),
          ...closures.map((item) => Card(
              child: ListTile(
                  title: Text(item['name'] as String),
                  subtitle:
                      Text((item['closure_reason'] as String?) ?? 'Closed')))),
          const SizedBox(height: 16),
          const Text('Active incidents',
              style: TextStyle(fontWeight: FontWeight.bold)),
          if (incidents.isEmpty)
            const Card(
              child: ListTile(
                leading: Icon(Icons.check_circle, color: Colors.green),
                title: Text('No active incidents'),
                subtitle: Text('All incidents have been resolved.'),
              ),
            )
          else
            ...incidents
                .where((item) => item['status'] == 'ACTIVE')
                .map((item) => Card(
                      child: ListTile(
                        title: Text('${item['type']} - ${item['severity']}'),
                        subtitle: Text('Status: ${item['status']}'),
                        trailing: IconButton(
                          onPressed: () =>
                              resolveIncident(item['id'] as String),
                          icon: const Icon(Icons.check_circle,
                              color: Colors.green),
                          tooltip: 'Mark as resolved',
                        ),
                      ),
                    )),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(
      {required this.label, required this.value, required this.color});
  final String label;
  final String value;
  final Color color;
  @override
  Widget build(BuildContext context) => Card(
      child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            Text(value,
                style: Theme.of(context)
                    .textTheme
                    .headlineMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.bold)),
            Text(label, textAlign: TextAlign.center)
          ])));
}
