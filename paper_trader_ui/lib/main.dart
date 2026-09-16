import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:action_slider/action_slider.dart';
import 'package:http/http.dart' as http;
import 'package:interactive_chart/interactive_chart.dart';
import 'api_config.dart';

void main() => runApp(const ProTradingApp());

class ProTradingApp extends StatelessWidget {
  const ProTradingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dhan/Zerodha Pro Trader',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0C0E14),
        cardColor: const Color(0xFF131722),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF2962FF),
          secondary: Color(0xFFF23645),
        ),
      ),
      home: const MainDashboard(),
    );
  }
}

class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});
  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  int _tab = 0;
  final screens = const [
    WatchlistScreen(),
    OrdersScreen(),
    PortfolioScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: screens[_tab],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        backgroundColor: const Color(0xFF131722),
        selectedItemColor: const Color(0xFF2962FF),
        unselectedItemColor: Colors.grey,
        onTap: (i) => setState(() => _tab = i),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.show_chart), label: 'Watchlist'),
          BottomNavigationBarItem(icon: Icon(Icons.menu_book), label: 'Orders'),
          BottomNavigationBarItem(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Portfolio'),
        ],
      ),
    );
  }
}

class StockQuote {
  final String symbol;
  final String exchange;
  final double ltp;
  final double change;
  final double pct;
  const StockQuote(this.symbol, this.exchange, this.ltp, this.change, this.pct);
}

class WatchlistScreen extends StatefulWidget {
  const WatchlistScreen({super.key});
  @override
  State<WatchlistScreen> createState() => _WatchlistScreenState();
}

class _WatchlistScreenState extends State<WatchlistScreen> {
  final cur = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
  List<StockQuote> stocks = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchQuotes();
  }

  Future<void> fetchQuotes() async {
    setState(() => loading = true);
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/quotes'));
      if (res.statusCode == 200) {
        final List data = jsonDecode(res.body);
        setState(() {
          stocks = data.map((q) => StockQuote(
            q['symbol'],
            q['exchange'],
            (q['ltp'] as num).toDouble(),
            (q['change'] as num).toDouble(),
            (q['percentChange'] as num).toDouble(),
          )).toList();
          loading = false;
        });
      }
    } catch (_) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131722),
        elevation: 0,
        title: const Text('Market Watch (NSE)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: fetchQuotes)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: fetchQuotes,
              child: ListView.separated(
                itemCount: stocks.length,
                separatorBuilder: (_, _) => const Divider(color: Color(0xFF1E222D), height: 1),
                itemBuilder: (context, i) {
                  final s = stocks[i];
                  final isUp = s.change >= 0;
                  return ListTile(
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => StockDetailScreen(stock: s)),
                    ),
                    title: Text(s.symbol, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    subtitle: Text(s.exchange, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(cur.format(s.ltp), style: TextStyle(fontWeight: FontWeight.bold, color: isUp ? const Color(0xFF089981) : const Color(0xFFF23645))),
                        Text('${isUp ? '+' : ''}${s.change.toStringAsFixed(2)} (${s.pct.toStringAsFixed(2)}%)', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class StockDetailScreen extends StatefulWidget {
  final StockQuote stock;
  const StockDetailScreen({super.key, required this.stock});
  @override
  State<StockDetailScreen> createState() => _StockDetailScreenState();
}

class _StockDetailScreenState extends State<StockDetailScreen> {
  List<CandleData> candleData = [];
  Map<String, dynamic>? depth;
  bool loading = true;
  String selectedTf = "15m";
  final List<String> timeframes = ["1m", "5m", "15m", "1h", "1d"];

  double? hO, hH, hL, hC;

  @override
  void initState() {
    super.initState();
    loadChartAndDepth();
  }

  Future<void> loadChartAndDepth() async {
    setState(() => loading = true);
    try {
      final chartRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/charts/${widget.stock.symbol}?interval=$selectedTf'));
      final depthRes = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/depth/${widget.stock.symbol}'));

      if (chartRes.statusCode == 200 && depthRes.statusCode == 200) {
        final List d = jsonDecode(chartRes.body);
        final mDepth = jsonDecode(depthRes.body);

        if (d.length >= 3) {
          final candles = d.map((c) => CandleData(
            timestamp: c['timestamp'],
            open: (c['open'] as num).toDouble(),
            high: (c['high'] as num).toDouble(),
            low: (c['low'] as num).toDouble(),
            close: (c['close'] as num).toDouble(),
            volume: (c['volume'] as num).toDouble(),
          )).toList();

          setState(() {
            candleData = candles;
            depth = mDepth;
            loading = false;
            hO = candles.last.open;
            hH = candles.last.high;
            hL = candles.last.low;
            hC = candles.last.close;
          });
          return;
        }
      }
      setState(() => loading = false);
    } catch (_) {
      setState(() => loading = false);
    }
  }

  Widget _buildTimeframePill(String tf) {
    final bool isSel = selectedTf == tf;
    return GestureDetector(
      onTap: () {
        if (selectedTf != tf) {
          selectedTf = tf;
          loadChartAndDepth();
        }
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSel ? const Color(0xFF2962FF).withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSel ? const Color(0xFF2962FF) : const Color(0xFF2A2E39)),
        ),
        child: Text(tf.toUpperCase(), style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: isSel ? const Color(0xFF2962FF) : Colors.grey)),
      ),
    );
  }

  Widget _buildMarketDepthPanel() {
    if (depth == null) return const SizedBox.shrink();
    final bids = depth!['bids'] as List;
    final asks = depth!['asks'] as List;

    return Container(
      padding: const EdgeInsets.all(12),
      color: const Color(0xFF131722),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Market Depth (5-Level Book)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Column(
                  children: bids.map((b) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${b['quantity']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('${b['orders']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('${b['price']}', style: const TextStyle(fontSize: 11, color: Color(0xFF089981), fontWeight: FontWeight.bold)),
                    ],
                  )).toList(),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: asks.map((a) => Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${a['price']}', style: const TextStyle(fontSize: 11, color: Color(0xFFF23645), fontWeight: FontWeight.bold)),
                      Text('${a['orders']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('${a['quantity']}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                    ],
                  )).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF131722),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.stock.symbol, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('₹${widget.stock.ltp.toStringAsFixed(2)}', style: TextStyle(fontSize: 12, color: widget.stock.change >= 0 ? const Color(0xFF089981) : const Color(0xFFF23645))),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(12),
        color: const Color(0xFF131722),
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2962FF), padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => OrderSheet(stock: widget.stock, defaultSide: true),
                ),
                child: const Text('BUY', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF23645), padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () => showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => OrderSheet(stock: widget.stock, defaultSide: false),
                ),
                child: const Text('SELL', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFF131722),
                    child: Row(
                      children: [
                        ...timeframes.map((tf) => _buildTimeframePill(tf)),
                        const Spacer(),
                        const Text('EMA (9, 21)', style: TextStyle(fontSize: 11, color: Colors.blueAccent)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    color: const Color(0xFF0C0E14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('O: ${hO?.toStringAsFixed(2) ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('H: ${hH?.toStringAsFixed(2) ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('L: ${hL?.toStringAsFixed(2) ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        Text('C: ${hC?.toStringAsFixed(2) ?? "--"}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                  SizedBox(
                    height: 380,
                    child: InteractiveChart(
                      candles: candleData,
                      style: const ChartStyle(
                        volumeHeightFactor: 0.2,
                        priceGainColor: Color(0xFF089981),
                        priceLossColor: Color(0xFFF23645),
                        volumeColor: Color(0x33787B86),
                        priceGridLineColor: Color(0xFF1E222D),
                      ),
                      onTap: (c) {
                        setState(() {
                          hO = c.open;
                          hH = c.high;
                          hL = c.low;
                          hC = c.close;
                        });
                      },
                    ),
                  ),
                  _buildMarketDepthPanel(),
                ],
              ),
            ),
    );
  }
}

class PortfolioScreen extends StatefulWidget {
  const PortfolioScreen({super.key});
  @override
  State<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends State<PortfolioScreen> {
  double cash = 0.0;
  double totalPnl = 0.0;
  List positions = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    try {
      final r = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/portfolio'));
      if (r.statusCode == 200) {
        final d = jsonDecode(r.body);
        setState(() {
          cash = (d['virtual_cash'] as num).toDouble();
          totalPnl = (d['total_pnl'] as num).toDouble();
          positions = d['positions'];
          loading = false;
        });
      }
    } catch (_) {
      setState(() => loading = false);
    }
  }

  Future<void> exitPosition(String sym, String product) async {
    try {
      final res = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/api/v1/positions/square-off'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'user_id': 1, 'symbol': sym, 'product': product}),
      );
      final d = jsonDecode(res.body);
      if (d['result']['status'] == 'FILLED') {
        load();
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131722),
        title: const Text('Portfolio & Funds', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: load)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: load,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFF131722), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Virtual Cash', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text('₹${NumberFormat('#,##,###.##').format(cash)}', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(color: const Color(0xFF131722), borderRadius: BorderRadius.circular(8)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Unrealized P&L', style: TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 4),
                              Text(
                                '${totalPnl >= 0 ? '+' : ''}₹${totalPnl.toStringAsFixed(2)}',
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: totalPnl >= 0 ? const Color(0xFF089981) : const Color(0xFFF23645)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('Positions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  if (positions.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 40), child: Center(child: Text('No active open positions.')))
                  else
                    ...positions.map((p) {
                      final pnl = (p['pnl'] as num).toDouble();
                      final isGreen = pnl >= 0;
                      return Card(
                        color: const Color(0xFF131722),
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Row(
                            children: [
                              Text(p['symbol'], style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                                decoration: BoxDecoration(color: const Color(0xFF2A2E39), borderRadius: BorderRadius.circular(3)),
                                child: Text(p['product'], style: const TextStyle(fontSize: 9, color: Colors.blueAccent)),
                              ),
                            ],
                          ),
                          subtitle: Text('Qty: ${p['quantity']} • Avg: ₹${p['avg_price']} • LTP: ₹${p['ltp']}'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${isGreen ? '+' : ''}₹$pnl', style: TextStyle(fontWeight: FontWeight.bold, color: isGreen ? const Color(0xFF089981) : const Color(0xFFF23645))),
                              const SizedBox(width: 8),
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF23645), visualDensity: VisualDensity.compact),
                                onPressed: () => exitPosition(p['symbol'], p['product']),
                                child: const Text('EXIT', style: TextStyle(fontSize: 11)),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});
  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  List orders = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchOrders();
  }

  Future<void> fetchOrders() async {
    try {
      final res = await http.get(Uri.parse('${ApiConfig.baseUrl}/api/v1/orders'));
      if (res.statusCode == 200) {
        setState(() {
          orders = jsonDecode(res.body);
          loading = false;
        });
      }
    } catch (_) {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF131722),
        title: const Text('Order Book', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        actions: [IconButton(icon: const Icon(Icons.refresh), onPressed: fetchOrders)],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : orders.isEmpty
              ? const Center(child: Text('No orders placed today.'))
              : ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const Divider(color: Color(0xFF1E222D), height: 1),
                  itemBuilder: (context, i) {
                    final o = orders[i];
                    final isFilled = o['status'] == 'FILLED';
                    return ListTile(
                      title: Text('${o['side']} ${o['symbol']} (${o['product']})', style: TextStyle(fontWeight: FontWeight.bold, color: o['side'] == 'BUY' ? const Color(0xFF2962FF) : const Color(0xFFF23645))),
                      subtitle: Text('${o['order_type']} • Qty: ${o['quantity']} • ${o['time']}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(isFilled ? '₹${o['executed_price']}' : o['status'], style: TextStyle(fontWeight: FontWeight.bold, color: isFilled ? const Color(0xFF089981) : Colors.orangeAccent)),
                          if (!isFilled && o['rejection_reason'] != null)
                            Text(o['rejection_reason'], style: const TextStyle(fontSize: 10, color: Colors.redAccent)),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class OrderSheet extends StatefulWidget {
  final StockQuote stock;
  final bool defaultSide;
  const OrderSheet({super.key, required this.stock, this.defaultSide = true});
  @override
  State<OrderSheet> createState() => _OrderSheetState();
}

class _OrderSheetState extends State<OrderSheet> {
  late bool isBuy;
  bool isMIS = true;
  String orderType = "MARKET";
  int qty = 1;
  double? limitPrice;

  @override
  void initState() {
    super.initState();
    isBuy = widget.defaultSide;
    limitPrice = widget.stock.ltp;
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = isBuy ? const Color(0xFF2962FF) : const Color(0xFFF23645);
    final marginRequired = isMIS ? (widget.stock.ltp * qty / 5.0) : (widget.stock.ltp * qty);

    return Container(
      decoration: const BoxDecoration(color: Color(0xFF131722), borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      padding: EdgeInsets.only(left: 20, right: 20, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('${widget.stock.symbol} (NSE)', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('₹${widget.stock.ltp}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              ChoiceChip(
                label: const Text('Intraday MIS (5x)'),
                selected: isMIS,
                onSelected: (val) => setState(() => isMIS = true),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Longterm CNC (1x)'),
                selected: !isMIS,
                onSelected: (val) => setState(() => isMIS = false),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              ChoiceChip(
                label: const Text('MARKET'),
                selected: orderType == 'MARKET',
                onSelected: (v) => setState(() => orderType = 'MARKET'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('LIMIT'),
                selected: orderType == 'LIMIT',
                onSelected: (v) => setState(() => orderType = 'LIMIT'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: '1',
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
                  onChanged: (v) => setState(() => qty = int.tryParse(v) ?? 1),
                ),
              ),
              if (orderType == 'LIMIT') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: widget.stock.ltp.toString(),
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Limit Price', border: OutlineInputBorder()),
                    onChanged: (v) => setState(() => limitPrice = double.tryParse(v) ?? widget.stock.ltp),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: Text('Margin Required: ₹${marginRequired.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ),
          const SizedBox(height: 18),
          ActionSlider.standard(
            backgroundColor: const Color(0xFF0C0E14),
            toggleColor: themeColor,
            icon: const Icon(Icons.arrow_forward, color: Colors.white),
            action: (controller) async {
              controller.loading();
              try {
                final res = await http.post(
                  Uri.parse('${ApiConfig.baseUrl}/api/v1/orders/place'),
                  headers: {'Content-Type': 'application/json'},
                  body: jsonEncode({
                    'user_id': 1,
                    'symbol': widget.stock.symbol,
                    'side': isBuy ? 'BUY' : 'SELL',
                    'product': isMIS ? 'MIS' : 'CNC',
                    'order_type': orderType,
                    'quantity': qty,
                    'limit_price': orderType == 'LIMIT' ? limitPrice : null,
                  }),
                );
                final d = jsonDecode(res.body);
                if (d['result']['status'] == 'FILLED' || d['result']['status'] == 'PENDING') {
                  controller.success();
                  await Future.delayed(const Duration(milliseconds: 300));
                  if (mounted) Navigator.pop(context);
                } else {
                  throw Exception(d['result']['message']);
                }
              } catch (e) {
                controller.reset();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Order Rejected: $e'), backgroundColor: Colors.red));
                }
              }
            },
            child: Text('SWIPE TO ${isBuy ? "BUY" : "SELL"}', style: TextStyle(color: themeColor, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}