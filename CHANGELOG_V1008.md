# Changelog v1.008 — TrocZen

Mise à jour du 18 février 2026 : avatars utilisateurs, upload IPFS, vraie synchronisation P3 Nostr, widget image cachée.

---

## Nouvelles dépendances

```yaml
# pubspec.yaml
image_picker: ^1.0.0
cached_network_image: ^3.3.0
path: ^1.8.3
```

---

## Modèles mis à jour

### User — champ `picture`
```dart
class User {
  // ...
  final String? picture;  // URL avatar (IPFS ou locale)
}
```
Inclus dans `toJson()` / `fromJson()`.

### Bon — champ `picture`
```dart
class Bon {
  // ...
  final String? picture;  // Avatar de l'émetteur
}
```
Inclus dans `copyWith()`, `toJson()`, `fromJson()`.

### NostrProfile — `picture` déjà présent (NIP-01 natif)

---

## Onboarding — Sélection d'avatar (`onboarding_profile_screen.dart`)

### Interface
- Avatar circulaire 120×120 cliquable, bordure orange
- Affiche l'image sélectionnée ou une icône par défaut
- Indicateur de chargement pendant l'upload

### Sélection
```dart
void _pickProfileImage() async {
  final XFile? image = await _imagePicker.pickImage(
    source: ImageSource.gallery,
    maxWidth: 800,
    imageQuality: 85,
  );
  if (image != null) setState(() => _selectedProfileImage = File(image.path));
}
```

### Upload lors de la sauvegarde
```dart
if (_selectedProfileImage != null) {
  final uploadService = ImageUploadService(apiUrl: state.apiUrl);
  final result = await uploadService.uploadAvatar(
    imagePath: _selectedProfileImage!.path,
    npub: tempNpub,
  );
  if (result.success) pictureUrl = result.preferredUrl; // IPFS si dispo
}
```
L'upload échoue silencieusement — le profil est toujours créé.

---

## Vraie synchronisation P3 (`onboarding_nostr_sync_screen.dart`)

Remplacement de la simulation par une connexion WebSocket réelle :

```dart
// 1. Connexion au relais
final connected = await nostrService.connect(relayUrl);

// 2. Callback temps réel
nostrService.onP3Received = (bonId, p3Hex) async {
  receivedP3s.add({'bonId': bonId, 'p3': p3Hex});
  setState(() => _currentStep = 'Réception... (${receivedP3s.length} trouvés)');
};

// 3. Abonnement kind:30303
await nostrService.subscribeToMarket(marketName);
// Timeout 5s, puis stockage en cache
```

Déchiffrement automatique via `CryptoService.decryptP3WithSeed()` avec K_day dérivée de `seed_market + date`.

---

## PaniniCard — CachedNetworkImage

Remplacement de `Image.network` par `CachedNetworkImage` :

```dart
CachedNetworkImage(
  imageUrl: widget.bon.logoUrl!,
  width: 60, height: 60, fit: BoxFit.cover,
  placeholder: (context, url) => CircularProgressIndicator(...),
  errorWidget: (context, url, error) => Icon(_getDefaultIcon(rarity)),
  cacheKey: '${bon.issuerNpub}_${bon.logoUrl!.hashCode}',
)
```

**Avantages :** cache automatique, placeholder animé, disponible hors-ligne après premier chargement.

---

## Nouveaux fichiers

| Fichier | Rôle |
|---------|------|
| `lib/services/image_upload_service.dart` | Upload avatar vers API (IPFS ou local) |
| `lib/services/image_cache_service.dart` | Cache local des images téléchargées |
| `lib/widgets/cached_profile_image.dart` | Widget avatar réutilisable |

### Widget `CachedProfileImage`
```dart
CachedProfileImage(
  imageUrl: user.picture,
  npub: user.npub,
  size: 60,
  defaultIcon: Icons.person,
)
```

---

## Réponse API upload

```json
{
  "success": true,
  "preferredUrl": "https://ipfs.copylaradio.com/ipfs/QmXXX/avatar.png",
  "ipfsCid": "QmXXXXXXXXXXXXXX",
  "storage": "ipfs"
}
```
Si IPFS indisponible : `storage: "local"`, URL relative `/uploads/...`.

---

## Checklist v1.008

- [x] Modèle `User` + champ `picture`
- [x] Modèle `Bon` + champ `picture`
- [x] Picker image dans onboarding
- [x] Upload vers API + IPFS
- [x] Sync P3 réelle via NostrService
- [x] Déchiffrement avec `seed_market`
- [x] Stockage P3 en cache SQLite
- [x] CachedNetworkImage dans PaniniCard
- [x] Widget `CachedProfileImage` réutilisable
- [x] Gestion d'état via OnboardingNotifier
- [ ] Compression côté client (`flutter_image_compress`)
- [ ] Crop image avant upload
- [ ] Sync P3 incrémentale (filtre `since`)
