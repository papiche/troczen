import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:graphview/GraphView.dart';
import 'package:provider/provider.dart';
import '../../services/storage_service.dart';
import '../../services/nostr_service.dart';
import '../../services/cache_database_service.dart';
import '../../models/nostr_profile.dart';

class CircuitsGraphView extends StatefulWidget {
  const CircuitsGraphView({super.key});

  @override
  State<CircuitsGraphView> createState() => _CircuitsGraphViewState();
}

class _CircuitsGraphViewState extends State<CircuitsGraphView> with SingleTickerProviderStateMixin {
  late Future<List<TransferEdge>> _edgesFuture;
  List<TransferEdge> _allEdges = [];
  List<String> _bootstrapUsers = [];
  List<String> _contacts = [];
  String? _selectedNpub;

  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  final SugiyamaConfiguration _configuration = SugiyamaConfiguration()
    ..nodeSeparation = 50
    ..levelSeparation = 100
    ..orientation = SugiyamaConfiguration.ORIENTATION_TOP_BOTTOM;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 2.0, end: 6.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _loadData();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  void _loadData() {
    final storageService = Provider.of<StorageService>(context, listen: false);
    
    storageService.getBootstrapUsers().then((users) {
      if (mounted) setState(() => _bootstrapUsers = users);
    });
    
    storageService.getContacts().then((contacts) {
      if (mounted) setState(() => _contacts = contacts);
    });

    _edgesFuture = storageService.getTransferSummary().then((edges) async {
      if (edges.length > 200) {
        final limitedEdges = await storageService.getTransferSummary(limitDays: 30);
        _allEdges = limitedEdges;
        return limitedEdges;
      }
      _allEdges = edges;
      return edges;
    });
  }

  Graph _buildGraph(List<TransferEdge> edges) {
    final graph = Graph()..isTree = false;
    final nodes = <String, Node>{};

    Node getNode(String npub) {
      if (!nodes.containsKey(npub)) {
        nodes[npub] = Node.Id(npub);
      }
      return nodes[npub]!;
    }

    for (final edge in edges) {
      final fromNode = getNode(edge.fromNpub);
      final toNode = getNode(edge.toNpub);

      bool isFocused = false;
      bool isDimmed = false;

      if (_selectedNpub != null) {
        if (edge.fromNpub == _selectedNpub || edge.toNpub == _selectedNpub) {
          isFocused = true;
        } else {
          isDimmed = true;
        }
      }

      bool isBootstrapEdge = _bootstrapUsers.contains(edge.fromNpub) || _bootstrapUsers.contains(edge.toNpub);

      final paint = Paint()
        ..strokeWidth = isFocused ? max(2.0, edge.totalValue / 5.0) : max(1.0, edge.totalValue / 10.0)
        ..color = isDimmed
            ? Colors.grey.withValues(alpha: 0.05)
            : (isFocused
                ? (edge.isLoop ? Colors.greenAccent : Colors.orange)
                : (edge.isLoop ? Colors.greenAccent : Colors.grey));
      
      // Si c'est un lien bootstrap, on pourrait le dessiner en pointillés,
      // mais graphview ne supporte pas nativement les pointillés via Paint.
      // On peut utiliser une couleur légèrement différente pour l'arête.
      if (isBootstrapEdge && !isFocused && !isDimmed) {
        paint.color = Colors.purpleAccent.withValues(alpha: 0.5);
      }
      
      graph.addEdge(fromNode, toNode, paint: paint);
    }

    return graph;
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
                _selectedNpub = null;
                _loadData();
              });
            },
          ),
        ],
      ),
      body: FutureBuilder<List<TransferEdge>>(
        future: _edgesFuture,
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

          final edges = snapshot.data;
          if (edges == null || edges.isEmpty) {
            return const Center(
              child: Text('Aucun circuit détecté sur ce marché.'),
            );
          }

          final graph = _buildGraph(edges);

          return Stack(
            children: [
              GestureDetector(
                onTap: () {
                  if (_selectedNpub != null) {
                    setState(() {
                      _selectedNpub = null;
                    });
                  }
                },
                child: InteractiveViewer(
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
                ),
              ),
              if (_selectedNpub != null)
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: _buildFocusCard(),
                ),
            ],
          );
        },
      ),
      floatingActionButton: _selectedNpub != null
          ? FloatingActionButton.extended(
              onPressed: () {
                setState(() {
                  _selectedNpub = null;
                });
              },
              icon: const Icon(Icons.filter_alt_off),
              label: const Text('Reset'),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }

  Widget _buildNodeWidget(String? npub) {
    if (npub == null) return const SizedBox();

    final nostrService = Provider.of<NostrService>(context, listen: false);
    
    bool isDimmed = false;
    if (_selectedNpub != null && _selectedNpub != npub) {
      // Check if this node is connected to the selected node
      bool isConnected = _allEdges.any((e) => 
        (e.fromNpub == _selectedNpub && e.toNpub == npub) || 
        (e.toNpub == _selectedNpub && e.fromNpub == npub)
      );
      if (!isConnected) {
        isDimmed = true;
      }
    }

    final isBootstrap = _bootstrapUsers.contains(npub);
    final isFollowed = _contacts.contains(npub);
    final shouldPulse = isBootstrap && !isFollowed;

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedNpub = npub;
        });
      },
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isDimmed ? 0.2 : 1.0,
        child: FutureBuilder<NostrProfile?>(
          future: nostrService.fetchUserProfile(npub),
          builder: (context, snapshot) {
            final profile = snapshot.data;
            final imageUrl = profile?.picture;
            final name = profile?.name ?? 'Anonyme';

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedBuilder(
                      animation: _pulseAnimation,
                      builder: (context, child) {
                        return Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _selectedNpub == npub
                                  ? Colors.orange
                                  : (isBootstrap ? Colors.purpleAccent : Colors.greenAccent),
                              width: _selectedNpub == npub
                                  ? 3
                                  : (shouldPulse ? _pulseAnimation.value : 2),
                            ),
                            boxShadow: _selectedNpub == npub ? [
                              BoxShadow(
                                color: Colors.orange.withValues(alpha: 0.5),
                                blurRadius: 10,
                                spreadRadius: 2,
                              )
                            ] : (shouldPulse ? [
                              BoxShadow(
                                color: Colors.purpleAccent.withValues(alpha: 0.5),
                                blurRadius: _pulseAnimation.value * 2,
                                spreadRadius: _pulseAnimation.value / 2,
                              )
                            ] : null),
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
                        );
                      },
                    ),
                    if (isBootstrap)
                      Positioned(
                        top: -5,
                        right: -5,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            shape: BoxShape.circle,
                          ),
                          child: const Text('🌱', style: TextStyle(fontSize: 12)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: _selectedNpub == npub ? FontWeight.bold : FontWeight.normal,
                    color: _selectedNpub == npub ? Colors.orange : Colors.white,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFocusCard() {
    if (_selectedNpub == null) return const SizedBox();

    double volumeIn = 0;
    double volumeOut = 0;
    final partners = <String>{};

    for (final edge in _allEdges) {
      if (edge.toNpub == _selectedNpub) {
        volumeIn += edge.totalValue;
        partners.add(edge.fromNpub);
      }
      if (edge.fromNpub == _selectedNpub) {
        volumeOut += edge.totalValue;
        partners.add(edge.toNpub);
      }
    }

    return Card(
      color: const Color(0xFF1E1E1E).withValues(alpha: 0.9),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Analyse des Flux',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.orange),
            ),
            const Divider(color: Colors.white24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildStatColumn('Entrant', '${volumeIn.toStringAsFixed(0)} Ẑ', Colors.greenAccent),
                _buildStatColumn('Sortant', '${volumeOut.toStringAsFixed(0)} Ẑ', Colors.redAccent),
                _buildStatColumn('Partenaires', '${partners.length}', Colors.blueAccent),
              ],
            ),
            const SizedBox(height: 12),
            if (_bootstrapUsers.contains(_selectedNpub) && !_contacts.contains(_selectedNpub))
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.purpleAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.purpleAccent.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    const Text(
                      '🌱 Nouvel arrivant : suivez-le pour l\'aider à débloquer son Dividende Universel.',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => _followUser(_selectedNpub!),
                      icon: const Icon(Icons.handshake),
                      label: const Text('Tisser le lien'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purpleAccent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            OutlinedButton.icon(
              onPressed: () {
                // TODO: Naviguer vers le profil complet
              },
              icon: const Icon(Icons.person_search, size: 18),
              label: const Text('Voir profil complet'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: const BorderSide(color: Colors.white54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _followUser(String npub) async {
    final storageService = Provider.of<StorageService>(context, listen: false);
    final nostrService = Provider.of<NostrService>(context, listen: false);

    try {
      final user = await storageService.getUser();
      if (user == null) throw Exception('Utilisateur non trouvé');

      await storageService.addContact(npub);
      final contacts = await storageService.getContacts();
      await nostrService.publishContactList(
        npub: user.npub,
        nsec: user.nsec,
        contactsNpubs: contacts,
      );
      
      HapticFeedback.heavyImpact();
      // TODO: Jouer un son de clochette
      
      if (mounted) {
        setState(() {
          _contacts = contacts;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lien tissé avec succès ! 🌱'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur lors du suivi : $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatColumn(String label, String value, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      ],
    );
  }
}
