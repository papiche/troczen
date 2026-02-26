import 'package:flutter/material.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';
import '../../services/nostr_service.dart';
import '../../models/nostr_profile.dart';

class CircuitsGraphView extends StatefulWidget {
  const CircuitsGraphView({super.key});

  @override
  State<CircuitsGraphView> createState() => _CircuitsGraphViewState();
}

class _CircuitsGraphViewState extends State<CircuitsGraphView> {
  late Future<Graph> _graphFuture;
  final SugiyamaConfiguration _configuration = SugiyamaConfiguration()
    ..nodeSeparation = 50
    ..levelSeparation = 100
    ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;

  @override
  void initState() {
    super.initState();
    _loadGraph();
  }

  void _loadGraph() {
    final storageService = Provider.of<StorageService>(context, listen: false);
    // On charge d'abord sans limite pour voir le nombre de transferts
    _graphFuture = storageService.buildCircuitsGraph().then((graph) async {
      if (graph.edges.length > 200) {
        // Si > 200, on limite aux 30 derniers jours
        return await storageService.buildCircuitsGraph(limitDays: 30);
      }
      return graph;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Circuits du Marché'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() {
                _loadGraph();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<Graph>(
        future: _graphFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 16),
                  Text('Cartographie des échanges en cours...'),
                ],
              ),
            );
          }

          if (snapshot.hasError) {
            return Center(
              child: Text('Erreur: ${snapshot.error}'),
            );
          }

          final graph = snapshot.data;
          if (graph == null || graph.nodeCount() == 0) {
            return const Center(
              child: Text('Aucun circuit détecté sur ce marché.'),
            );
          }

          return InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(100),
            minScale: 0.1,
            maxScale: 5.0,
            child: GraphView(
              graph: graph,
              algorithm: SugiyamaAlgorithm(_configuration),
              paint: Paint()
                ..color = Colors.grey
                ..strokeWidth = 1
                ..style = PaintingStyle.stroke,
              builder: (Node node) {
                final npub = node.key?.value as String?;
                return _buildNodeWidget(npub);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildNodeWidget(String? npub) {
    if (npub == null) return const SizedBox();

    final nostrService = Provider.of<NostrService>(context, listen: false);

    return FutureBuilder<NostrProfile?>(
      future: nostrService.fetchUserProfile(npub),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final imageUrl = profile?.picture;
        final name = profile?.name ?? 'Anonyme';

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.greenAccent, width: 2),
              ),
              child: ClipOval(
                child: imageUrl != null && imageUrl.isNotEmpty
                    ? Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const Icon(Icons.person),
                      )
                    : const Icon(Icons.person),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name,
              style: const TextStyle(fontSize: 10),
              overflow: TextOverflow.ellipsis,
            ),
          ],
        );
      },
    );
  }
}
