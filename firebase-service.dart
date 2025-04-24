import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hive/hive.dart';
import 'dart:async';

class FirebaseService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Box _sobrietyBox = Hive.box('sobriety_data');
  final Box _consumptionBox = Hive.box('consumption_logs');
  StreamSubscription? _connectivitySubscription;
  bool _isOnline = false;
  
  // Initialize Firebase service and set up connectivity listener
  Future<void> initialize() async {
    // Enable offline persistence for Firestore
    _firestore.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
    );
    
    // Check initial connectivity
    final connectivityResult = await Connectivity().checkConnectivity();
    _isOnline = connectivityResult != ConnectivityResult.none;
    
    // Set up connectivity listener
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((result) {
      final wasOnline = _isOnline;
      _isOnline = result != ConnectivityResult.none;
      
      // If we just came online, sync data
      if (!wasOnline && _isOnline) {
        syncData();
      }
    });
  }
  
  // Sync local data with Firebase
  Future<void> syncData() async {
    if (!_isOnline) return;
    
    try {
      // Get user ID (you'll need to implement authentication)
      // For this example, we'll use a fixed user ID
      const userId = 'user123';
      
      // Sync sobriety data
      final sobrietyData = {
        'start_time': _sobrietyBox.get('start_time'),
        'temptation_count': _sobrietyBox.get('temptation_count', defaultValue: 0),
        'slip_count': _sobrietyBox.get('slip_count', defaultValue: 0),
        'timer_active': _sobrietyBox.get('timer_active', defaultValue: false),
        'last_updated': FieldValue.serverTimestamp(),
      };
      
      await _firestore.collection('users').doc(userId).set(sobrietyData, SetOptions(merge: true));
      
      // Sync consumption logs
      final consumptionLogs = _consumptionBox.values.toList();
      
      // Get existing logs from Firestore to avoid duplicates
      final existingLogs = await _firestore.collection('users').doc(userId).collection('logs').get();
      final existingLogIds = existingLogs.docs.map((doc) => doc.id).toSet();
      
      // Add new logs
      for (var i = 0; i < consumptionLogs.length; i++) {
        final logId = 'log_${i}_${DateTime.now().millisecondsSinceEpoch}';
        if (!existingLogIds.contains(logId)) {
          await _firestore
              .collection('users')
              .doc(userId)
              .collection('logs')
              .doc(logId)
              .set(consumptionLogs[i]);
        }
      }
      
      // Fetch the latest data from Firestore to ensure we're in sync
      await _fetchLatestDataFromFirestore(userId);
      
    } catch (e) {
      print('Error syncing data: $e');
    }
  }
  
  // Fetch the latest data from Firestore
  Future<void> _fetchLatestDataFromFirestore(String userId) async {
    try {
      // Get sobriety data
      final userData = await _firestore.collection('users').doc(userId).get();
      if (userData.exists) {
        final data = userData.data()!;
        
        // Update local data only if Firestore data is newer
        if (data['start_time'] != null) {
          _sobrietyBox.put('start_time', data['start_time']);
        }
        if (data['temptation_count'] != null) {
          _sobrietyBox.put('temptation_count', data['temptation_count']);
        }
        if (data['slip_count'] != null) {
          _sobrietyBox.put('slip_count', data['slip_count']);
        }
        if (data['timer_active'] != null) {
          _sobrietyBox.put('timer_active', data['timer_active']);
        }
      }
      
      // Get consumption logs
      final logsSnapshot = await _firestore
          .collection('users')
          .doc(userId)
          .collection('logs')
          .orderBy('date', descending: true)
          .get();
      
      // Clear existing logs and add the ones from Firestore
      await _consumptionBox.clear();
      for (var doc in logsSnapshot.docs) {
        await _consumptionBox.add(doc.data());
      }
    } catch (e) {
      print('Error fetching data from Firestore: $e');
    }
  }
  
  // Clean up
  void dispose() {
    _connectivitySubscription?.cancel();
  }
}
