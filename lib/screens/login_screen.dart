import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db_helper.dart';
import '../models/user.dart';
import 'currency_converter.dart';

// Global variable to store the currently logged in user
UserModel? currentUser;

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;
  bool _rememberMe = false;

  @override
  void initState() {
    super.initState();
    // Check if user credentials are stored
    _checkSavedCredentials();
  }

  Future<void> _checkSavedCredentials() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final rememberMe = prefs.getBool('remember_me') ?? false;

      if (rememberMe) {
        final username = prefs.getString('username');
        final password = prefs.getString('password');

        if (username != null && password != null) {
          _usernameController.text = username;
          _passwordController.text = password;
          _rememberMe = true;

          // Special case for admin - always allow auto-login
          if (username == 'a' && password == 'a') {
            final dbHelper = DatabaseHelper.instance;
            final adminUser = await dbHelper.getUserByCredentials(
              username,
              password,
            );
            if (adminUser != null) {
              await _handleSuccessfulLogin(adminUser);
              return;
            }
          }

          // For regular users, attempt auto-login
          final dbHelper = DatabaseHelper.instance;

          // Only try auto-login if we can connect to the server (for non-admin users)
          if (!dbHelper.isOfflineMode || await dbHelper.retryConnection()) {
            await _login(autoLogin: true);
          }
        }
      }
    } catch (e) {
      debugPrint('Error checking saved credentials: $e');
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login({bool autoLogin = false}) async {
    if (!autoLogin && _formKey.currentState?.validate() != true) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    final username = _usernameController.text.trim();
    final password = _passwordController.text.trim();

    try {
      final dbHelper = DatabaseHelper.instance;

      // Special case for admin - can login even if server is offline
      if (username == 'a' && password == 'a') {
        // Admin login - proceed without checking server connection
        final user = await dbHelper.getUserByCredentials(username, password);
        if (user != null) {
          await _handleSuccessfulLogin(user);
        }
      } else {
        // Non-admin users require server connectivity
        if (dbHelper.isOfflineMode) {
          // Try to reconnect to server first
          final connected = await dbHelper.retryConnection();
          if (!connected) {
            setState(() {
              _errorMessage = 'Cannot login - Server connection required';
              _isLoading = false;
            });
            return;
          }
        }

        // Regular login for non-admin users
        final user = await dbHelper.getUserByCredentials(username, password);
        if (user != null) {
          await _handleSuccessfulLogin(user);
        } else {
          // Invalid credentials
          if (!autoLogin) {
            setState(() {
              _errorMessage = 'Invalid username or password';
              _isLoading = false;
            });
          } else {
            setState(() {
              _isLoading = false;
            });
          }
        }
      }
    } catch (e) {
      // Only show error message if not auto-login
      if (!autoLogin) {
        setState(() {
          _errorMessage = 'An error occurred: ${e.toString()}';
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleSuccessfulLogin(UserModel user) async {
    // Store credentials if remember me is checked
    if (_rememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', true);
      await prefs.setString('username', _usernameController.text.trim());
      await prefs.setString('password', _passwordController.text.trim());
    } else {
      // Clear saved credentials if remember me is unchecked
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', false);
      await prefs.remove('username');
      await prefs.remove('password');
    }

    if (!mounted) return;

    // Store the logged in user globally
    currentUser = user;

    // Login successful, navigate to main app
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => const ResponsiveCurrencyConverter(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Check if we're on a tablet in landscape mode
    final screenSize = MediaQuery.of(context).size;
    final isTablet = screenSize.width >= 600;
    final isLandscape = screenSize.width > screenSize.height;
    final isWideTablet = isTablet && isLandscape;

    final logoSize = isWideTablet ? 100.0 : 80.0;
    final titleFontSize = isWideTablet ? 32.0 : 28.0;
    final formWidth = isWideTablet ? 400.0 : double.infinity;

    return Scaffold(
      backgroundColor: Colors.blue.shade50,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isWideTablet ? 40.0 : 24.0),
          child:
              isWideTablet
                  ? _buildTabletLayout(logoSize, titleFontSize, formWidth)
                  : _buildMobileLayout(logoSize, titleFontSize),
        ),
      ),
    );
  }

  // Landscape tablet layout with side-by-side design
  Widget _buildTabletLayout(
    double logoSize,
    double titleFontSize,
    double formWidth,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Left side - logo and app name
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // App logo/icon with a decorated container
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.shade200.withOpacity(0.5),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.currency_exchange,
                  size: logoSize,
                  color: Colors.blue.shade700,
                ),
              ),
              const SizedBox(height: 24),

              // App name
              Text(
                'Currency Converter',
                style: TextStyle(
                  fontSize: titleFontSize,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),

              // App description or tagline
              Text(
                'Manage your currency exchanges\nwith ease and efficiency',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue.shade600,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // Spacer
        const SizedBox(width: 40),

        // Right side - login form
        Expanded(
          flex: 5,
          child: Container(
            constraints: BoxConstraints(maxWidth: formWidth),
            child: Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: _buildLoginForm(24.0),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Original mobile layout
  Widget _buildMobileLayout(double logoSize, double titleFontSize) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // App logo/icon
        Icon(
          Icons.currency_exchange,
          size: logoSize,
          color: Colors.blue.shade700,
        ),
        const SizedBox(height: 24),

        // App name
        Text(
          'Currency Converter',
          style: TextStyle(
            fontSize: titleFontSize,
            fontWeight: FontWeight.bold,
            color: Colors.blue.shade800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 48),

        // Login form
        Card(
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildLoginForm(16.0),
          ),
        ),
      ],
    );
  }

  // Extract login form to avoid duplication
  Widget _buildLoginForm(double borderRadius) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Login',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.blue.shade800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          // Username field
          TextFormField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username',
              prefixIcon: const Icon(Icons.person),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your username';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Password field
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () {
                  setState(() {
                    _obscurePassword = !_obscurePassword;
                  });
                },
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter your password';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),

          // Remember me checkbox
          Row(
            children: [
              Checkbox(
                value: _rememberMe,
                onChanged: (value) {
                  setState(() {
                    _rememberMe = value!;
                  });
                },
                activeColor: Colors.blue.shade700,
              ),
              const Text('Remember me'),
            ],
          ),

          const SizedBox(height: 16),

          // Error message
          if (_errorMessage.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Text(
                _errorMessage,
                style: const TextStyle(
                  color: Colors.red,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),

          // Login button
          ElevatedButton(
            onPressed: _isLoading ? null : () => _login(),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade700,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 16),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(borderRadius),
              ),
            ),
            child:
                _isLoading
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                    : const Text('Login'),
          ),
        ],
      ),
    );
  }
}
