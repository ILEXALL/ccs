import 'package:ccs_app/features/community/data/community_country.dart'
    show communityText;
import 'package:ccs_app/shared/models/countries.dart' show countryIsoCode;

bool profileRegionIsComplete(String city, String country) =>
    city.trim().isNotEmpty &&
    city.trim().length <= 120 &&
    countryIsoCode(country) != null;

String get requiredRegionMessage => communityText(
  en: 'Choose your country and enter your city to continue.',
  ru: 'Чтобы продолжить, выберите страну и введите город.',
  lv: 'Lai turpinātu, izvēlieties valsti un ievadiet pilsētu.',
);
