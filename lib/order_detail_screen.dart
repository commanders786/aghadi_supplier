import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:flutter/services.dart'; // For clipboard

class OrderDetailScreen extends StatefulWidget {
  final String orderId;

  const OrderDetailScreen({Key? key, required this.orderId}) : super(key: key);

  @override
  _OrderDetailScreenState createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  // Cache for product names to avoid repeated API calls
  static final Map<String, String> _productNameCache = {};

  @override
  void initState() {
    super.initState();
    print('OrderDetailScreen initialized with orderId: ${widget.orderId}');
  }

  // Classify product_id into categories
  String classifyProduct(String productId) {
    print('Classifying productId: $productId');
    final id = productId.toLowerCase();
    if (id.startsWith('veg')) return 'Vegetables';
    if (id.startsWith('gr')) return 'Store Items';
    if (id.startsWith('fr')) return 'Fruits';
    if (id.startsWith('fs')) return 'Fish';
    if (id.startsWith('sn')) return 'Snacks';
    if (id.startsWith('rs')) return 'Food';
    return 'Meat';
  }

  // Calculate total for a category
  double calculateCategoryTotal(List<dynamic> items) {
    print('Calculating total for ${items.length} items');
    return items.fold(
        0.0, (sum, item) => sum + (item['total'] as num).toDouble());
  }

  // Format items for copying, including category total
  String formatItemsForCopy(
      List<dynamic> items, Map<String, String> productNames) {
    print('Formatting ${items.length} items for copy');
    final buffer = StringBuffer();
    final category = classifyProduct(items.first['product_id'].toString());
    final categoryTotal = calculateCategoryTotal(items);
    buffer.writeln('$category (Total: ₹${categoryTotal.toStringAsFixed(2)}):');
    for (var item in items) {
      final productId = item['product_id'].toString();
      final productName =
          productNames[productId] ?? 'Unknown Product ($productId)';
      buffer.writeln(
          '- $productName, Qty: ${item['quantity']}, Total: ₹${item['total'].toStringAsFixed(2)}');
    }
    final result = buffer.toString();
    print('Formatted text for clipboard:\n$result');
    return result;
  }

  // Fetch order items with retry logic
  Future<List<dynamic>> fetchOrderItems(String orderId,
      {int retries = 2}) async {
    const String apiUrl =
        'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/order-items/all';
    print('Fetching order items for orderId: $orderId from $apiUrl');
    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final startTime = DateTime.now();
        final response = await http.get(
          Uri.parse('$apiUrl?order_id=$orderId'),
          headers: {
            'ngrok-skip-browser-warning': 'true',
            // Add authentication headers if required
            // 'Authorization': 'Bearer your_token',
          },
        );
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        print(
            'Order Items API took $duration ms, Status: ${response.statusCode}, Body: ${response.body}');

        if (response.statusCode == 200) {
          final json = jsonDecode(response.body);
          print('Parsed JSON response: $json');
          if (json['status'] == 'success') {
            final data = json['data'];
            print('Order items fetched: $data');
            return data;
          }
          throw Exception(
              'API returned unsuccessful status: ${json['status']} - ${json['message'] ?? response.body}');
        }
        throw Exception(
            'Failed to load order items: ${response.statusCode} - ${response.body}');
      } catch (e) {
        print('Attempt ${attempt + 1} failed: $e');
        if (attempt == retries - 1) {
          throw Exception(
              'Error fetching order items after $retries attempts: $e');
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    throw Exception('Error fetching order items: Max retries reached');
  }

  // Fetch product names with retry logic
  Future<Map<String, String>> fetchProductNames(List<String> productIds,
      {int retries = 2}) async {
    print('Fetching product names for productIds: $productIds');
    if (productIds.isEmpty) {
      print('No product IDs to fetch');
      return {};
    }

    // Return cached names if available
    final uncachedIds =
        productIds.where((id) => !_productNameCache.containsKey(id)).toList();
    print('Uncached IDs: $uncachedIds');
    if (uncachedIds.isEmpty) {
      final cachedNames = {
        for (var id in productIds) id: _productNameCache[id] ?? id
      };
      print('Returning cached names: $cachedNames');
      return cachedNames;
    }

    final productIdsQuery = uncachedIds.join(',');
    const String url =
        'https://python-whatsapp-bot-main-production-3c9c.up.railway.app/products';
    print('Fetching from $url with product_ids=$productIdsQuery');

    for (var attempt = 0; attempt < retries; attempt++) {
      try {
        final startTime = DateTime.now();
        final response = await http.get(
          Uri.parse('$url?product_ids=$productIdsQuery'),
          headers: {
            'ngrok-skip-browser-warning': 'true',
            // 'Authorization': 'Bearer your_ngrok_api_key',
          },
        );
        final duration = DateTime.now().difference(startTime).inMilliseconds;
        print(
            'Product Names API took $duration ms, Status: ${response.statusCode}, Body: ${response.body}');

        if (response.statusCode == 200) {
          final names = Map<String, String>.from(jsonDecode(response.body));
          print('Product names fetched: $names');
          _productNameCache.addAll(names);
          final result = {
            for (var id in productIds) id: _productNameCache[id] ?? id
          };
          print('Returning product names: $result');
          return result;
        }
        throw Exception(
            'Failed to load product names: ${response.statusCode} - ${response.body}');
      } catch (e) {
        print('Attempt ${attempt + 1} failed: $e');
        if (attempt == retries - 1) {
          print('Error fetching product names after $retries attempts: $e');
          final fallback = {
            for (var id in productIds) id: _productNameCache[id] ?? id
          };
          print('Returning fallback names: $fallback');
          return fallback;
        }
        await Future.delayed(const Duration(seconds: 1));
      }
    }
    final fallback = {
      for (var id in productIds) id: _productNameCache[id] ?? id
    };
    print('Max retries reached, returning fallback names: $fallback');
    return fallback;
  }

  // Refresh function to reload data
  Future<void> _refreshData() async {
    print('Refreshing data for orderId: ${widget.orderId}');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    print('Building OrderDetailScreen for orderId: ${widget.orderId}');
    return DefaultTabController(
      length: 1,
      child: Scaffold(
        appBar: AppBar(
          title: Text('Order ${widget.orderId}'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Order Details'),
            ],
          ),
        ),
        body: RefreshIndicator(
          onRefresh: _refreshData,
          child: TabBarView(
            children: [
              FutureBuilder<List<dynamic>>(
                future: fetchOrderItems(widget.orderId),
                builder: (context, orderSnapshot) {
                  print(
                      'OrderSnapshot state: ${orderSnapshot.connectionState}');
                  if (orderSnapshot.connectionState ==
                      ConnectionState.waiting) {
                    print('Showing loading indicator');
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (orderSnapshot.hasError) {
                    print('Error in orderSnapshot: ${orderSnapshot.error}');
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                              'Error: ${orderSnapshot.error.toString().split(':').last.trim()}'),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () => setState(() {}),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    );
                  }
                  final orderItems = orderSnapshot.data ?? [];
                  print('Order items received: $orderItems');
                  if (orderItems.isEmpty) {
                    print('No order items found');
                    return const Center(child: Text('No items found'));
                  }

                  // Extract product IDs
                  final productIds = orderItems
                      .map((item) => item['product_id'].toString())
                      .toList();
                  print('Extracted product IDs: $productIds');

                  return FutureBuilder<Map<String, String>>(
                    future: fetchProductNames(productIds),
                    builder: (context, productSnapshot) {
                      print(
                          'ProductSnapshot state: ${productSnapshot.connectionState}');
                      if (productSnapshot.connectionState ==
                          ConnectionState.waiting) {
                        print('Showing loading indicator for product names');
                        return const Center(child: CircularProgressIndicator());
                      }
                      final productNames = productSnapshot.data ?? {};
                      print('Product names received: $productNames');

                      // Group items by category
                      final Map<String, List<dynamic>> categorizedItems = {};
                      for (var item in orderItems) {
                        final productId = item['product_id'].toString();
                        final category = classifyProduct(productId);
                        categorizedItems
                            .putIfAbsent(category, () => [])
                            .add(item);
                      }
                      print('Categorized items: $categorizedItems');

                      return ListView.builder(
                        physics: const AlwaysScrollableScrollPhysics(),
                        itemCount: categorizedItems.length,
                        itemBuilder: (context, index) {
                          final category =
                              categorizedItems.keys.elementAt(index);
                          final items = categorizedItems[category]!;
                          final categoryTotal = calculateCategoryTotal(items);
                          print(
                              'Rendering category: $category, Total: $categoryTotal');

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 16, 16, 8),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '$category (₹${categoryTotal.toStringAsFixed(2)})',
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    ElevatedButton.icon(
                                      onPressed: () async {
                                        print(
                                            'Copy button pressed for category: $category');
                                        final text = formatItemsForCopy(
                                            items, productNames);
                                        await Clipboard.setData(
                                            ClipboardData(text: text));
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                          const SnackBar(
                                              content:
                                                  Text('Copied to clipboard!')),
                                        );
                                      },
                                      icon: const Icon(Icons.copy, size: 16),
                                      label: const Text('Copy'),
                                      style: ElevatedButton.styleFrom(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: items.length,
                                itemBuilder: (context, itemIndex) {
                                  final item = items[itemIndex];
                                  final productId =
                                      item['product_id'].toString();
                                  final productName = productNames[productId] ??
                                      'Unknown Product ($productId)';
                                  print(
                                      'Rendering item: $productName, Qty: ${item['quantity']}');
                                  return ListTile(
                                    title: Text(productName),
                                    subtitle:
                                        Text('Quantity: ${item['quantity']}'),
                                    trailing: Text(
                                        '₹${item['total'].toStringAsFixed(2)}'),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 4),
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
