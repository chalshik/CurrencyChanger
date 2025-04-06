import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'screens/login_screen.dart';
import 'screens/network_error_screen.dart';
import 'providers/language_provider.dart';
import 'providers/theme_provider.dart';

// Custom theme extension for additional text styling
class TextStyleExtension extends ThemeExtension<TextStyleExtension> {
  final TextStyle? regularText;
  final TextStyle? boldText;
  final TextStyle? subtitleText;

  TextStyleExtension({this.regularText, this.boldText, this.subtitleText});

  @override
  TextStyleExtension copyWith({
    TextStyle? regularText,
    TextStyle? boldText,
    TextStyle? subtitleText,
  }) {
    return TextStyleExtension(
      regularText: regularText ?? this.regularText,
      boldText: boldText ?? this.boldText,
      subtitleText: subtitleText ?? this.subtitleText,
    );
  }

  @override
  TextStyleExtension lerp(ThemeExtension<TextStyleExtension>? other, double t) {
    if (other is! TextStyleExtension) {
      return this;
    }
    return TextStyleExtension(
      regularText: TextStyle.lerp(regularText, other.regularText, t),
      boldText: TextStyle.lerp(boldText, other.boldText, t),
      subtitleText: TextStyle.lerp(subtitleText, other.subtitleText, t),
    );
  }
}

void main() async {
  // Ensure Flutter is initialized
  WidgetsFlutterBinding.ensureInitialized();

  // Determine if running on a tablet
  final size = WidgetsBinding.instance.window.physicalSize;
  final devicePixelRatio = WidgetsBinding.instance.window.devicePixelRatio;
  final width = size.width / devicePixelRatio;
  final isTablet = width >= 600;

  // Only force portrait on phones, allow both orientations on tablets
  if (!isTablet) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
  } else {
    // Allow all orientations on tablets
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => LanguageProvider()),
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
      ],
      child: const MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    final languageProvider = Provider.of<LanguageProvider>(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return MaterialApp(
      title: 'Currency Converter',
      debugShowCheckedModeBanner: false,
      locale: languageProvider.currentLocale,
      supportedLocales: const [
        Locale('ky'), // Kyrgyz
        Locale('ru'), // Russian
        Locale('en'), // English
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: themeProvider.lightTheme.copyWith(
        extensions: <ThemeExtension<dynamic>>[
          TextStyleExtension(
            regularText: const TextStyle(color: Colors.black, fontSize: 16),
            boldText: const TextStyle(
              color: Colors.black,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            subtitleText: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
      darkTheme: themeProvider.darkTheme.copyWith(
        extensions: <ThemeExtension<dynamic>>[
          TextStyleExtension(
            regularText: const TextStyle(color: Colors.white, fontSize: 16),
            boldText: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
            subtitleText: TextStyle(color: Colors.grey.shade300, fontSize: 14),
          ),
        ],
      ),
      themeMode: themeProvider.themeMode,
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _isCheckingConnectivity = false;

  @override
  void initState() {
    super.initState();
    _checkConnectivityAndNavigate();
  }

  Future<void> _checkConnectivityAndNavigate() async {
    setState(() {
      _isCheckingConnectivity = true;
    });

    try {
      // Simulate loading time for 2 seconds to show splash screen
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      // Check network connectivity
      var connectivityResult = await Connectivity().checkConnectivity();
      if (connectivityResult == ConnectivityResult.none) {
        // No network connectivity
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => NetworkErrorScreen(
                onRetry: () async {
                  // When retry is pressed, check connectivity again
                  try {
                    debugPrint("Retry callback triggered");
                    var result = await Connectivity().checkConnectivity();
                    
                    if (result != ConnectivityResult.none) {
                      // If there's connectivity, navigate to login screen
                      if (mounted) {
                        debugPrint("Connectivity restored, navigating to login screen");
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(builder: (context) => const LoginScreen()),
                        );
                        return true; // Return true to indicate successful navigation
                      }
                    }
                    debugPrint("No connectivity or not mounted, return false");
                    return false; // Return false to indicate connectivity still not available
                  } catch (e) {
                    debugPrint("Error in retry callback: $e");
                    return false;
                  }
                },
              ),
            ),
          );
        }
      } else {
        // Has network connectivity, proceed to login screen
        if (mounted) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (context) => const LoginScreen()),
          );
        }
      }
    } catch (e) {
      debugPrint('Error checking connectivity: $e');
      // In case of error, proceed to login screen
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const LoginScreen()),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingConnectivity = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            // Main content in center
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // App logo/icon
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade700.withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.currency_exchange,
                        size: 100,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // App name
                    Text(
                      "Currency Exchanger",
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            // "By" and logo at bottom
            Container(
              margin: const EdgeInsets.only(bottom: 32),
              child: Column(
                children: [
                  // "BY" text
                  Text(
                    "BY",
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2.0,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // User logo
                  Image.asset(
                    'assets/images/logo.png',
                    width: 250,
                    height: 80,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
