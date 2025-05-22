import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:vibration/vibration.dart';
import 'package:clipboard/clipboard.dart';
import 'order_detail_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  try {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'order_channel',
      'Order Notifications',
      description: 'Notifications for new orders',
      importance: Importance.high,
      playSound: true,
    );

    final androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.requestNotificationsPermission();

    bool? initialized = await flutterLocalNotificationsPlugin
        .initialize(initializationSettings);
    print(
        'Notifications initialized: ${initialized == true ? 'Success' : 'Failed'}');
  } catch (e) {
    print('Notification initialization error: $e');
  }

  runApp(MyApp());
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: OrderListScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class Order {
  final String orderId;
  final String createdAt;
  final int itemCount;
  final String status;

  Order({
    required this.orderId,
    required this.createdAt,
    required this.itemCount,
    required this.status,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      orderId: json['order_id'],
      createdAt: json['created_at'],
      itemCount: json['item_count'],
      status: json['status'],
    );
  }
}

class User {
  final String id;
  final String createdAt;
  final String language;
  final String lastLogin;
  final String name;
  final String phone;

  User({
    required this.id,
    required this.createdAt,
    required this.language,
    required this.lastLogin,
    required this.name,
    required this.phone,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'].toString(),
      createdAt: json['created_at'],
      language: json['language'],
      lastLogin: json['lastlogin'],
      name: json['name'],
      phone: json['phone'],
    );
  }
}

class OrderListScreen extends StatefulWidget {
  @override
  _OrderListScreenState createState() => _OrderListScreenState();
}

class _OrderListScreenState extends State<OrderListScreen>
    with SingleTickerProviderStateMixin {
  List<Order> orders = [];
  List<User> users = [];
  List<String> previousOrderIds = [];
  bool isLoadingOrders = true;
  bool isLoadingUsers = true;
  String? errorMessageOrders;
  String? errorMessageUsers;
  String? searchQueryOrders = '';
  String? searchQueryUsers = '';
  String? selectedStatus = 'All';
  DateTime? selectedOrderDate;
  DateTime? selectedJoinDate;
  DateTime? selectedLastLogin;
  Timer? _pollingTimer;
  TabController? _tabController;

  // IST timezone offset (+5:30)
  final istOffset = Duration(hours: 5, minutes: 30);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    fetchOrders();
    fetchUsers();
    startPolling();
  }

  void startPolling() {
    _pollingTimer = Timer.periodic(Duration(minutes: 1), (timer) {
      checkForNewOrders();
    });
  }

  Future<void> showOrderNotification(String orderId) async {
    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
        'order_channel',
        'Order Notifications',
        channelDescription: 'Notifications for new orders',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        ticker: 'ticker',
      );

      const NotificationDetails platformDetails =
          NotificationDetails(android: androidDetails);

      await flutterLocalNotificationsPlugin.show(
        0,
        'New Order Received!',
        'Order ID: $orderId',
        platformDetails,
      );
      print('Notification shown for Order ID: $orderId');
    } catch (e) {
      print('Notification error: $e');
    }
  }

  Future<void> vibrateDevice() async {
    try {
      bool? hasVibrator = await Vibration.hasVibrator();
      if (hasVibrator == true) {
        Vibration.vibrate(duration: 500);
        print('Vibration triggered');
      } else {
        print('Device does not support vibration');
      }
    } catch (e) {
      print('Vibration error: $e');
    }
  }

  Future<String?> fetchReceipt(String orderId) async {
    try {
      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse(
            'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/reciept?order_id=$orderId'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print(
          'Receipt API took $duration ms, Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData['order_id'] == orderId) {
          return jsonData['reciept'] as String?;
        } else {
          print('Receipt API error: Invalid order_id');
          return null;
        }
      } else {
        print('Receipt API HTTP error: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Receipt API error: $e');
      return null;
    }
  }

  void showReceiptDialog(String orderId) async {
    final receipt = await fetchReceipt(orderId);
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Receipt for Order ID: $orderId'),
          content: SingleChildScrollView(
            child: receipt != null
                ? Text(
                    receipt,
                    style: TextStyle(fontSize: 14),
                  )
                : Text('Failed to load receipt'),
          ),
          actions: [
            if (receipt != null)
              TextButton(
                onPressed: () {
                  FlutterClipboard.copy(receipt).then((_) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Receipt copied to clipboard')),
                    );
                  });
                },
                child: Text('Copy'),
              ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> checkForNewOrders() async {
    try {
      final startTime = DateTime.now();
      final response = await http.get(
        Uri.parse(
            'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/orders/summary'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      final duration = DateTime.now().difference(startTime).inMilliseconds;
      print(
          'Orders API took $duration ms, Status: ${response.statusCode}, Body: ${response.body}');

      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData['status'] == 'success') {
          List<Order> newOrders = (jsonData['data'] as List)
              .map((item) => Order.fromJson(item))
              .toList();

          List<String> newOrderIds = newOrders.map((o) => o.orderId).toList();
          List<String> diff = newOrderIds
              .where((id) => !previousOrderIds.contains(id))
              .toList();
          print('Previous IDs: $previousOrderIds');
          print('New IDs: $newOrderIds');
          print('New orders detected: $diff');

          if (diff.isNotEmpty) {
            await showOrderNotification(diff.first);
            await vibrateDevice();
          } else {
            print('No new orders');
          }

          setState(() {
            orders = newOrders;
            previousOrderIds = newOrderIds;
          });
        } else {
          print('API error: ${jsonData['status']}');
        }
      } else {
        print('HTTP error: ${response.statusCode}');
      }
    } catch (e) {
      print('Polling error: $e');
    }
  }

  Future<void> fetchOrders() async {
    setState(() {
      isLoadingOrders = true;
      errorMessageOrders = null;
    });
    try {
      final response = await http.get(
        Uri.parse(
            'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/orders/summary'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        if (jsonData['status'] == 'success') {
          setState(() {
            orders = (jsonData['data'] as List)
                .map((item) => Order.fromJson(item))
                .toList();
            previousOrderIds = orders.map((o) => o.orderId).toList();
            isLoadingOrders = false;
          });
        } else {
          setState(() {
            isLoadingOrders = false;
            errorMessageOrders = 'Failed to load orders: ${jsonData['status']}';
          });
        }
      } else {
        setState(() {
          isLoadingOrders = false;
          errorMessageOrders = 'Failed to load orders: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isLoadingOrders = false;
        errorMessageOrders = 'Error fetching orders: $e';
      });
    }
  }

  Future<void> fetchUsers() async {
    setState(() {
      isLoadingUsers = true;
      errorMessageUsers = null;
    });
    try {
      final response = await http.get(
        Uri.parse(
            'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/users'),
        headers: {'ngrok-skip-browser-warning': 'true'},
      );
      if (response.statusCode == 200) {
        final jsonData = jsonDecode(response.body);
        setState(() {
          users =
              (jsonData as List).map((item) => User.fromJson(item)).toList();
          isLoadingUsers = false;
        });
      } else {
        setState(() {
          isLoadingUsers = false;
          errorMessageUsers = 'Failed to load users: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        isLoadingUsers = false;
        errorMessageUsers = 'Error fetching users: $e';
      });
    }
  }

  // Convert GMT date string to IST DateTime
  DateTime parseDateToIST(String dateStr) {
    final gmtDate = DateFormat('EEE, dd MMM yyyy HH:mm:ss').parse(dateStr);
    return gmtDate.add(istOffset);
  }

  // Format DateTime to IST string
  String formatDateToIST(DateTime date) {
    return DateFormat('yyyy-MM-dd HH:mm:ss').format(date);
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _tabController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    List<Order> filteredOrders = orders.where((order) {
      bool matchesStatus = selectedStatus == 'All' ||
          order.status.toLowerCase() == selectedStatus!.toLowerCase();
      bool matchesSearch = order.orderId.contains(searchQueryOrders ?? '');
      bool matchesDate = selectedOrderDate == null ||
          parseDateToIST(order.createdAt)
              .toString()
              .startsWith(DateFormat('yyyy-MM-dd').format(selectedOrderDate!));
      return matchesStatus && matchesSearch && matchesDate;
    }).toList();

    List<User> filteredUsers = users.where((user) {
      bool matchesSearch = user.phone.contains(searchQueryUsers ?? '');
      bool matchesJoinDate = selectedJoinDate == null ||
          parseDateToIST(user.createdAt)
              .toString()
              .startsWith(DateFormat('yyyy-MM-dd').format(selectedJoinDate!));
      bool matchesLastLogin = selectedLastLogin == null ||
          parseDateToIST(user.lastLogin)
              .toString()
              .startsWith(DateFormat('yyyy-MM-dd').format(selectedLastLogin!));
      return matchesSearch && matchesJoinDate && matchesLastLogin;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text('Dashboard', style: TextStyle(color: Colors.white)),
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: 'Orders'),
            Tab(text: 'Users'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Orders Tab
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            searchQueryOrders = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search by Order ID...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.filter_list, color: Colors.green),
                      onPressed: () {
                        showOrderFilterDialog();
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total Orders: ${filteredOrders.length}',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                isLoadingOrders
                    ? Expanded(
                        child: Center(child: CircularProgressIndicator()))
                    : errorMessageOrders != null
                        ? Expanded(
                            child: Center(child: Text(errorMessageOrders!)))
                        : filteredOrders.isEmpty
                            ? Expanded(
                                child:
                                    Center(child: Text('No orders available')))
                            : Expanded(
                                child: ListView.builder(
                                  itemCount: filteredOrders.length,
                                  itemBuilder: (context, index) {
                                    final order = filteredOrders[index];
                                    return Card(
                                      margin: EdgeInsets.symmetric(vertical: 8),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.all(16),
                                        title:
                                            Text('Order ID: ${order.orderId}'),
                                        subtitle: Text(
                                            'Date: ${formatDateToIST(parseDateToIST(order.createdAt))}\nItems: ${order.itemCount}'),
                                        trailing: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            IconButton(
                                              icon: Icon(Icons.visibility,
                                                  color: Color.fromARGB(
                                                      255, 15, 219, 15)),
                                              onPressed: () {
                                                print(
                                                    'Showing receipt for Order ID: ${order.orderId}');
                                                showReceiptDialog(
                                                    order.orderId);
                                              },
                                            ),
                                            CircleAvatar(
                                              backgroundColor: order.status ==
                                                      'pending'
                                                  ? Colors.red
                                                  : order.status == 'picked up'
                                                      ? Colors.yellow
                                                      : Colors.green,
                                              child: Text(
                                                order.status[0].toUpperCase(),
                                                style: TextStyle(
                                                    color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                        onTap: () {
                                          print(
                                              'Navigating to OrderDetailScreen for order: ${order.orderId}');
                                          Navigator.push(
                                            context,
                                            MaterialPageRoute(
                                              builder: (context) =>
                                                  OrderDetailScreen(
                                                      orderId: order.orderId),
                                            ),
                                          );
                                        },
                                      ),
                                    );
                                  },
                                ),
                              ),
              ],
            ),
          ),
          // Users Tab
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        onChanged: (value) {
                          setState(() {
                            searchQueryUsers = value;
                          });
                        },
                        decoration: InputDecoration(
                          hintText: 'Search by Phone Number...',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.search),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.filter_list, color: Colors.green),
                      onPressed: () {
                        showUserFilterDialog();
                      },
                    ),
                  ],
                ),
                SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Total Users: ${filteredUsers.length}',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                SizedBox(height: 8),
                isLoadingUsers
                    ? Expanded(
                        child: Center(child: CircularProgressIndicator()))
                    : errorMessageUsers != null
                        ? Expanded(
                            child: Center(child: Text(errorMessageUsers!)))
                        : filteredUsers.isEmpty
                            ? Expanded(
                                child:
                                    Center(child: Text('No users available')))
                            : Expanded(
                                child: ListView.builder(
                                  itemCount: filteredUsers.length,
                                  itemBuilder: (context, index) {
                                    final user = filteredUsers[index];
                                    return Card(
                                      margin: EdgeInsets.symmetric(vertical: 8),
                                      child: ListTile(
                                        contentPadding: EdgeInsets.all(16),
                                        title: Text('Name: ${user.name}'),
                                        subtitle: Text(
                                            'Phone: ${user.phone}\nJoined: ${formatDateToIST(parseDateToIST(user.createdAt))}\nLast Login: ${formatDateToIST(parseDateToIST(user.lastLogin))}'),
                                      ),
                                    );
                                  },
                                ),
                              ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void showOrderFilterDialog() async {
    // Use stateful variables to track dialog state
    String? tempStatus = selectedStatus;
    DateTime? tempOrderDate = selectedOrderDate;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Filter Orders'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempOrderDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2101),
                      );
                      if (pickedDate != null) {
                        setDialogState(() {
                          tempOrderDate = pickedDate;
                        });
                      }
                    },
                    child: Text(
                      'Order Date: ${tempOrderDate != null ? DateFormat('yyyy-MM-dd').format(tempOrderDate!) : 'None'}',
                    ),
                  ),
                  DropdownButton<String>(
                    value: tempStatus,
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        tempStatus = newValue;
                      });
                    },
                    items: ['All', 'Pending', 'Picked Up', 'Delivered']
                        .map<DropdownMenuItem<String>>((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedOrderDate = null;
                      selectedStatus = 'All';
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text('Reset'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedOrderDate = tempOrderDate;
                      selectedStatus = tempStatus;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void showUserFilterDialog() async {
    // Use stateful variables to track dialog state
    DateTime? tempJoinDate = selectedJoinDate;
    DateTime? tempLastLogin = selectedLastLogin;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Filter Users'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempJoinDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2101),
                      );
                      if (pickedDate != null) {
                        setDialogState(() {
                          tempJoinDate = pickedDate;
                        });
                      }
                    },
                    child: Text(
                      'Join Date: ${tempJoinDate != null ? DateFormat('yyyy-MM-dd').format(tempJoinDate!) : 'None'}',
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      final DateTime? pickedDate = await showDatePicker(
                        context: context,
                        initialDate: tempLastLogin ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2101),
                      );
                      if (pickedDate != null) {
                        setDialogState(() {
                          tempLastLogin = pickedDate;
                        });
                      }
                    },
                    child: Text(
                      'Last Login: ${tempLastLogin != null ? DateFormat('yyyy-MM-dd').format(tempLastLogin!) : 'None'}',
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedJoinDate = null;
                      selectedLastLogin = null;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text('Reset'),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      selectedJoinDate = tempJoinDate;
                      selectedLastLogin = tempLastLogin;
                    });
                    Navigator.of(context).pop();
                  },
                  child: Text('Apply'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
