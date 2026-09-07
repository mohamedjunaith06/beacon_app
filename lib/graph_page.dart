import 'package:flutter/material.dart';
import 'main.dart'; // For PacketStatus and PacketHistoryProvider classes

class GraphPage extends StatefulWidget {
  final PacketHistoryProvider packetHistoryProvider;
  final VoidCallback onClear;

  const GraphPage({
    super.key,
    required this.packetHistoryProvider,
    required this.onClear,
  });

  @override
  State<GraphPage> createState() => _GraphPageState();
}

class _GraphPageState extends State<GraphPage> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    // Listen to changes to auto-scroll
    widget.packetHistoryProvider.addListener(_onHistoryChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEnd();
    });
  }

  @override
  void didUpdateWidget(covariant GraphPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.packetHistoryProvider != widget.packetHistoryProvider) {
      oldWidget.packetHistoryProvider.removeListener(_onHistoryChanged);
      widget.packetHistoryProvider.addListener(_onHistoryChanged);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToEnd();
    });
  }

  @override
  void dispose() {
    widget.packetHistoryProvider.removeListener(_onHistoryChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onHistoryChanged() {
    if (mounted) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.2), width: 1),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 16.0),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey[800],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.packetHistoryProvider,
      builder: (context, _) {
        final packetHistory = widget.packetHistoryProvider.history;
        final totalExpected = packetHistory.length;
        final received = packetHistory.where((p) => p.received).length;
        final missed = totalExpected - received;
        final lossRate = totalExpected > 0 ? (missed / totalExpected * 100) : 0.0;

        return Scaffold(
          appBar: AppBar(
            title: const Text("Packet Receipt History"),
            centerTitle: true,
            actions: [
              TextButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Clear Data"),
                      content: const Text("Are you sure you want to clear all packet history and reset tracking?"),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("Cancel"),
                        ),
                        TextButton(
                          onPressed: () {
                            widget.onClear();
                            Navigator.pop(context);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
                          child: const Text("Clear"),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
                label: const Text(
                  "Clear",
                  style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stats Grid
                Row(
                  children: [
                    Expanded(child: _buildStatCard("Total Expected", totalExpected.toString(), Icons.playlist_add_check_rounded, Colors.blue)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard("Received (Active)", received.toString(), Icons.check_circle_outline_rounded, Colors.teal)),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _buildStatCard("Missed (Inactive)", missed.toString(), Icons.error_outline_rounded, Colors.redAccent)),
                    const SizedBox(width: 12),
                    Expanded(child: _buildStatCard("Packet Loss", "${lossRate.toStringAsFixed(1)}%", Icons.trending_down_rounded, Colors.orange)),
                  ],
                ),
                const SizedBox(height: 24),
                
                // Section title
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        "Timeline Graph (2s Interval)",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
                        ),
                      ),
                      if (packetHistory.isNotEmpty)
                        Expanded(
                          child: Text(
                            "Scroll horizontally",
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[500],
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Graph Container
                Container(
                  height: 260,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.blueGrey[900], // Premium dark background
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.15),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: packetHistory.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.query_stats_rounded, size: 48, color: Colors.blueGrey[300]),
                              const SizedBox(height: 12),
                              Text(
                                "No packets recorded yet",
                                style: TextStyle(
                                  color: Colors.blueGrey[200],
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                "Start scanning on the home page",
                                style: TextStyle(
                                  color: Colors.blueGrey[400],
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Scrollbar(
                          controller: _scrollController,
                          thumbVisibility: true,
                          child: SingleChildScrollView(
                            controller: _scrollController,
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.only(bottom: 16.0),
                            child: CustomPaint(
                              size: Size(
                                (packetHistory.length * 40.0) + 80.0,
                                220,
                              ),
                              painter: PacketChartPainter(
                                packetHistory: packetHistory,
                                slotWidth: 40.0,
                              ),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }
}

class PacketChartPainter extends CustomPainter {
  final List<PacketStatus> packetHistory;
  final double slotWidth;

  const PacketChartPainter({
    required this.packetHistory,
    required this.slotWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (packetHistory.isEmpty) return;

    final paintActiveDot = Paint()
      ..color = const Color(0xFF10B981) // Modern Emerald Green
      ..style = PaintingStyle.fill;

    final paintActiveGlow = Paint()
      ..color = const Color(0xFF10B981).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final paintInactiveDot = Paint()
      ..color = const Color(0xFFEF4444) // Modern Crimson Red
      ..style = PaintingStyle.fill;

    final paintInactiveGlow = Paint()
      ..color = const Color(0xFFEF4444).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;

    final paintLine = Paint()
      ..color = Colors.blueGrey.withValues(alpha: 0.4)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final paintGrid = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final textPainter = TextPainter(
      textDirection: TextDirection.ltr,
    );

    // Padding settings
    const double topPadding = 50.0;
    const double bottomPadding = 50.0;
    final double plotHeight = size.height - topPadding - bottomPadding;
    
    // Y coords (height 0 = Active, height 1 = Inactive)
    const double yInactive = topPadding; // height 1 (Inactive)
    final double yActive = topPadding + plotHeight; // height 0 (Active)

    // Draw horizontal reference grid lines
    canvas.drawLine(const Offset(0, yInactive), Offset(size.width, yInactive), paintGrid);
    canvas.drawLine(Offset(0, yActive), Offset(size.width, yActive), paintGrid);

    // Draw Y labels
    _drawText(canvas, textPainter, "Inactive / Missed (Y=1)", const Offset(12, topPadding - 32), const Color(0xFFFCA5A5), 11, FontWeight.bold);
    _drawText(canvas, textPainter, "Active / Received (Y=0)", Offset(12, yActive + 14), const Color(0xFFA7F3D0), 11, FontWeight.bold);

    // Create a path to connect dots
    final path = Path();
    final List<Offset> points = [];

    for (int i = 0; i < packetHistory.length; i++) {
      final status = packetHistory[i];
      final double x = i * slotWidth + 40.0; // Left margin offset
      final double y = status.received ? yActive : yInactive;
      points.add(Offset(x, y));

      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    // Draw connecting lines
    if (points.length > 1) {
      canvas.drawPath(path, paintLine);
    }

    // Draw dots and vertical grid lines/labels
    for (int i = 0; i < packetHistory.length; i++) {
      final status = packetHistory[i];
      final double x = points[i].dx;
      final double y = points[i].dy;

      // Draw vertical slot line
      canvas.drawLine(Offset(x, yInactive - 5), Offset(x, yActive + 5), paintGrid);

      // Draw dot glow
      canvas.drawCircle(Offset(x, y), 9.0, status.received ? paintActiveGlow : paintInactiveGlow);
      // Draw dot center
      canvas.drawCircle(Offset(x, y), 5.0, status.received ? paintActiveDot : paintInactiveDot);

      // Draw bottom timeline label: relative time (every 2s)
      final String elapsedStr = "${i * 2}s";
      _drawCenteredText(canvas, textPainter, elapsedStr, Offset(x, yActive + 22), Colors.blueGrey[300]!, 10, FontWeight.normal);

      // Draw top timeline label: beacon counter
      final String counterStr = "#${status.counter}";
      _drawCenteredText(canvas, textPainter, counterStr, Offset(x, yInactive - 20), Colors.blueGrey[200]!, 9, FontWeight.w500);
    }
  }

  void _drawText(Canvas canvas, TextPainter textPainter, String text, Offset offset, Color color, double fontSize, FontWeight fontWeight) {
    textPainter.text = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    textPainter.layout();
    textPainter.paint(canvas, offset);
  }

  void _drawCenteredText(Canvas canvas, TextPainter textPainter, String text, Offset offset, Color color, double fontSize, FontWeight fontWeight) {
    textPainter.text = TextSpan(
      text: text,
      style: TextStyle(
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
      ),
    );
    textPainter.layout();
    final Offset centeredOffset = Offset(offset.dx - textPainter.width / 2, offset.dy);
    textPainter.paint(canvas, centeredOffset);
  }

  @override
  bool shouldRepaint(covariant PacketChartPainter oldDelegate) {
    return oldDelegate.packetHistory != packetHistory;
  }
}
