import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String offerCatalogUrl = String.fromEnvironment(
  'OFFER_CATALOG_URL',
  defaultValue: 'data/offers/offers.json',
);
const String offerSiteBaseUrl = 'https://today-music.pages.dev/';

class OfferedDataPackage {
  final String id;
  final bool enabled;
  final bool notify;
  final String title;
  final String artistLabel;
  final String description;
  final String note;
  final String dataPath;
  final DateTime startAt;
  final DateTime endAt;
  final String primaryButton;
  final String secondaryButton;

  const OfferedDataPackage({
    required this.id,
    required this.enabled,
    required this.notify,
    required this.title,
    required this.artistLabel,
    required this.description,
    required this.note,
    required this.dataPath,
    required this.startAt,
    required this.endAt,
    required this.primaryButton,
    required this.secondaryButton,
  });

  factory OfferedDataPackage.fromJson(Map<String, Object?> json) {
    final startAt = DateTime.tryParse(_requiredText(json, 'startAt'));
    final endAt = DateTime.tryParse(_requiredText(json, 'endAt'));
    if (startAt == null || endAt == null || endAt.isBefore(startAt)) {
      throw const FormatException('Offer dates are invalid.');
    }

    return OfferedDataPackage(
      id: _requiredText(json, 'id'),
      enabled: json['enabled'] == true,
      notify: json['notify'] != false,
      title: _requiredText(json, 'title'),
      artistLabel: _requiredText(json, 'artistLabel'),
      description: _requiredText(json, 'description'),
      note: _requiredText(json, 'note'),
      dataPath: _requiredText(json, 'dataPath'),
      startAt: startAt,
      endAt: endAt,
      primaryButton: _requiredText(json, 'primaryButton'),
      secondaryButton: _requiredText(json, 'secondaryButton'),
    );
  }

  bool isActiveAt(DateTime now) {
    return enabled && notify && !now.isBefore(startAt) && !now.isAfter(endAt);
  }
}

abstract interface class OfferRepository {
  Future<List<OfferedDataPackage>> loadCatalog();

  Future<String> loadData(OfferedDataPackage offer);
}

class HttpOfferRepository implements OfferRepository {
  final String catalogUrl;
  final Future<http.Response> Function(Uri uri) fetch;

  const HttpOfferRepository({
    this.catalogUrl = offerCatalogUrl,
    this.fetch = http.get,
  });

  @override
  Future<List<OfferedDataPackage>> loadCatalog() async {
    try {
      final resolvedCatalogUrl = resolveOfferUrl(catalogUrl);
      final response = await fetch(Uri.parse(resolvedCatalogUrl));
      if (response.statusCode != 200) {
        debugPrint(
          'Offer catalog load failed: $resolvedCatalogUrl / '
          'status ${response.statusCode}',
        );
        return const [];
      }

      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map || decoded['offers'] is! List) {
        return const [];
      }

      return (decoded['offers'] as List)
          .whereType<Map>()
          .map(
            (item) =>
                OfferedDataPackage.fromJson(Map<String, Object?>.from(item)),
          )
          .toList();
    } catch (error) {
      debugPrint('Offer catalog load error: $error');
      return const [];
    }
  }

  @override
  Future<String> loadData(OfferedDataPackage offer) async {
    final resolvedDataUrl = resolveOfferUrl(offer.dataPath);
    final response = await fetch(Uri.parse(resolvedDataUrl));
    if (response.statusCode != 200) {
      throw StateError(
        'Offer data request failed with status ${response.statusCode}.',
      );
    }
    return utf8.decode(response.bodyBytes, allowMalformed: true);
  }
}

String resolveOfferUrl(String path) {
  final trimmed = path.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri != null && uri.hasScheme) {
    return trimmed;
  }

  if (kIsWeb) {
    return Uri.base.resolve(trimmed).toString();
  }

  final normalizedPath = trimmed.startsWith('/')
      ? trimmed.substring(1)
      : trimmed;
  return Uri.parse(offerSiteBaseUrl).resolve(normalizedPath).toString();
}

List<OfferedDataPackage> activeUnseenOffers({
  required Iterable<OfferedDataPackage> offers,
  required DateTime now,
  required Set<String> seenOfferIds,
  required Set<String> importedOfferIds,
}) {
  return offers
      .where(
        (offer) =>
            offer.isActiveAt(now) &&
            !seenOfferIds.contains(offer.id) &&
            !importedOfferIds.contains(offer.id),
      )
      .toList()
    ..sort((left, right) => left.startAt.compareTo(right.startAt));
}

String _requiredText(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('$key must be a non-empty string.');
  }
  return value.trim();
}
