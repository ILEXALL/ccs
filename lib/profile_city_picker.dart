import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ProfileCity {
  final int id;
  final String name, region;
  final double latitude, longitude;
  final List<String> aliases;
  String? qualifiedName;
  String get selectionName => qualifiedName ?? name;
  ProfileCity(List<dynamic> row)
    : id = row[0] as int,
      name = row[1] as String,
      region = row[2] as String,
      latitude = (row[3] as num).toDouble(),
      longitude = (row[4] as num).toDouble(),
      aliases = (row[6] as List).cast<String>();
  bool matches(String query) => [
    name,
    ...aliases,
  ].any((name) => name.toLowerCase().contains(query.toLowerCase()));
  bool named(String query) => [
    selectionName,
    name,
    ...aliases,
  ].any((name) => name.toLowerCase() == query.trim().toLowerCase());
}

final _cityCache = <String, List<ProfileCity>>{};
List<ProfileCity> parseCities(String source) {
  final rows = (jsonDecode(source) as List)
      .map((row) => ProfileCity(row as List))
      .toList(growable: false);
  final names = <String, int>{};
  for (final city in rows) {
    names[city.name] = (names[city.name] ?? 0) + 1;
  }
  for (final city in rows) {
    if (names[city.name]! > 1 && city.region.isNotEmpty)
      city.qualifiedName = city.name + ', ' + city.region;
  }
  return rows;
}

Future<List<ProfileCity>> citiesForCountry(String code) async {
  if (_cityCache.containsKey(code)) return _cityCache[code]!;
  final source = await rootBundle.loadString('assets/cities/$code.json');
  final cities = await compute(parseCities, source);
  _cityCache[code] = cities;
  return cities;
}

Future<ProfileCity?> resolveProfileCity(String code, String city) async {
  if (code.isEmpty || city.trim().isEmpty) return null;
  for (final place in await citiesForCountry(code)) {
    if (place.named(city)) return place;
  }
  return null;
}

class ProfileCityField extends StatelessWidget {
  final String? countryCode;
  final TextEditingController controller;
  final String label;
  final bool enabled;
  const ProfileCityField({
    super.key,
    required this.countryCode,
    required this.controller,
    this.label = 'City',
    this.enabled = true,
  });
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('city-${countryCode ?? "none"}'),
    controller: controller,
    readOnly: true,
    enabled: enabled && countryCode != null,
    decoration: InputDecoration(
      labelText: label,
      prefixIcon: const Icon(Icons.location_city),
      suffixIcon: const Icon(Icons.expand_more),
      hintText: countryCode == null ? 'Select country first' : 'Select city',
    ),
    validator: (value) => (value ?? '').trim().isEmpty ? 'Select a city' : null,
    onTap: () async {
      final city = await showModalBottomSheet<ProfileCity>(
        context: context,
        isScrollControlled: true,
        builder: (_) =>
            CitySearchSheet(countryCode: countryCode!, title: label),
      );
      if (city != null && context.mounted) controller.text = city.selectionName;
    },
  );
}

class CitySearchSheet extends StatefulWidget {
  final String countryCode, title;
  const CitySearchSheet({
    super.key,
    required this.countryCode,
    required this.title,
  });
  @override
  State<CitySearchSheet> createState() => _CitySearchSheetState();
}

class _CitySearchSheetState extends State<CitySearchSheet> {
  late Future<List<ProfileCity>> cities = citiesForCountry(widget.countryCode);
  String search = '';
  @override
  Widget build(BuildContext context) => SafeArea(
    child: SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          children: [
            Text(widget.title, style: Theme.of(context).textTheme.titleLarge),
            TextField(
              autofocus: true,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Search city',
              ),
              onChanged: (value) => setState(() => search = value.trim()),
            ),
            Expanded(
              child: FutureBuilder<List<ProfileCity>>(
                future: cities,
                builder: (context, snapshot) {
                  if (snapshot.hasError)
                    return Center(
                      child: TextButton(
                        onPressed: () => setState(
                          () => cities = citiesForCountry(widget.countryCode),
                        ),
                        child: const Text('Retry'),
                      ),
                    );
                  if (!snapshot.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final rows = snapshot.data!
                      .where((city) => city.matches(search))
                      .toList(growable: false);
                  if (rows.isEmpty)
                    return const Center(child: Text('No matching cities'));
                  return ListView.builder(
                    itemCount: rows.length,
                    itemBuilder: (context, i) => ListTile(
                      title: Text(rows[i].name),
                      subtitle: Text(rows[i].region),
                      onTap: () => Navigator.pop(context, rows[i]),
                    ),
                  );
                },
              ),
            ),
            const Text(
              'City data © GeoNames · CC BY 4.0',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}
