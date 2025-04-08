import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(ProviderScope(child: Buy3App()));
}

class Buy3App extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BUY3 Signal',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
      ),
      home: StockSignalScreen(),
    );
  }
}

class StockSignalScreen extends ConsumerStatefulWidget {
  @override
  ConsumerState<StockSignalScreen> createState() => _StockSignalScreenState();
}

class _StockSignalScreenState extends ConsumerState<StockSignalScreen> {
  final List<String> tickers = ['005930.KS', '000660.KS', '035420.KQ'];
  Map<String, DateTime?> lastBuyDates = {};

  @override
  void initState() {
    super.initState();
    _loadBuyDates();
  }

  Future<void> _loadBuyDates() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      for (var ticker in tickers) {
        final dateStr = prefs.getString('buy_$ticker');
        if (dateStr != null) {
          lastBuyDates[ticker] = DateTime.tryParse(dateStr);
        }
      }
    });
  }

  Future<void> _saveBuyDate(String ticker) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('buy_$ticker', DateTime.now().toIso8601String());
    setState(() {
      lastBuyDates[ticker] = DateTime.now();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('BUY3 매수신호')),
      body: ListView(
        children: tickers.map((ticker) => StockTile(
          ticker: ticker,
          lastBuyDate: lastBuyDates[ticker],
          onBuy: () => _saveBuyDate(ticker),
        )).toList(),
      ),
    );
  }
}

final stockProvider = FutureProvider.family<StockData, String>((ref, ticker) async {
  final url = Uri.parse('https://buy3-api.onrender.com/stock/$ticker');
  final response = await http.get(url);

  if (response.statusCode == 200) {
    final json = jsonDecode(response.body);
    return StockData(
      close: List<double>.from(json['close']),
      ma20: List<double>.from(json['ma20']),
      vpt: List<double>.from(json['vpt']),
    );
  } else {
    throw Exception('API 오류 발생');
  }
});

class StockTile extends ConsumerWidget {
  final String ticker;
  final DateTime? lastBuyDate;
  final VoidCallback onBuy;

  StockTile({required this.ticker, this.lastBuyDate, required this.onBuy});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stockDataAsync = ref.watch(stockProvider(ticker));
    final today = DateTime.now();

    return Card(
      margin: EdgeInsets.all(8),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: stockDataAsync.when(
          data: (data) {
            final daysSinceBuy = lastBuyDate != null ? today.difference(lastBuyDate!).inDays : 1000;
            final signal = evaluateBuySignal(data, daysSinceBuy);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(ticker, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                SizedBox(height: 8),
                Text('현재가: ${data.close.last.toStringAsFixed(2)}'),
                Text('20일선: ${data.ma20.last.toStringAsFixed(2)}'),
                Text('VPT 매수신호: ${signal.vptSignal ? 'O' : '-'}'),
                SizedBox(height: 8),
                Text('BUY 신호: ${signal.buySignal ? '매수 타이밍!' : '대기'}',
                    style: TextStyle(
                        color: signal.buySignal ? Colors.green : Colors.black)),
                SizedBox(height: 8),
                Text('최근 매수일: ${lastBuyDate != null ? DateFormat('yyyy-MM-dd').format(lastBuyDate!) : '없음'}'),
                if (signal.buySignal)
                  ElevatedButton(
                    onPressed: onBuy,
                    child: Text('매수일 저장'),
                  ),
              ],
            );
          },
          loading: () => CircularProgressIndicator(),
          error: (e, st) => Text('에러: $e'),
        ),
      ),
    );
  }
}

class StockData {
  final List<double> close;
  final List<double> ma20;
  final List<double> vpt;

  StockData({required this.close, required this.ma20, required this.vpt});
}

class BuySignalResult {
  final bool buySignal;
  final bool vptSignal;
  BuySignalResult({required this.buySignal, required this.vptSignal});
}

BuySignalResult evaluateBuySignal(StockData data, int daysSinceBuy) {
  final prices = data.close;
  final ma20 = data.ma20;
  final vpt = data.vpt;

  bool condition30days = daysSinceBuy > 30;
  bool belowMA20 = prices.last < ma20.last;
  bool threeDaysDown = prices.length >= 4 &&
    prices[prices.length - 1] < prices[prices.length - 2] &&
    prices[prices.length - 2] < prices[prices.length - 3] &&
    prices[prices.length - 3] < prices[prices.length - 4];

  bool vptSignal = vpt.length > 2 && vpt[vpt.length - 1] > vpt[vpt.length - 2];

  return BuySignalResult(
    buySignal: condition30days && belowMA20 && threeDaysDown,
    vptSignal: vptSignal,
  );
}
